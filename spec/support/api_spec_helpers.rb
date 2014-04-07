require 'and_feathers'
require 'and_feathers/gzipped_tarball'
require 'tempfile'
require 'mixlib/authentication/signedheaderauth'

module ApiSpecHelpers
  def share_cookbook(cookbook_name, options = {})
    if options.has_key?(:user)
      user = options[:user]
    else
      user = create(:user)
      user.accounts << create(:account, provider: 'chef_oauth2', username: 'supermarket')
    end

    category = create(:category, name: options.fetch(:category, 'other').titleize)

    private_key = OpenSSL::PKey::RSA.new(
      File.read("spec/support/key_fixtures/#{options.fetch(:private_key, 'valid_private_key.pem')}")
    )

    metadata = {
      name: cookbook_name,
      version: '1.0.0',
      description: "Installs/Configures #{cookbook_name}",
      maintainer: 'Chef Software, Inc',
      license: 'MIT',
      platforms: {
        'ubuntu' => '>= 12.0.0'
      },
      dependencies: {
        'apt' => '~> 1.0.0'
      }
    }.merge(options.fetch(:custom_metadata, {}))

    tarball = Tempfile.new([cookbook_name, '.tgz'], 'tmp').tap do |file|
      io = AndFeathers.build(cookbook_name) do |base_dir|
        base_dir.file('README.md') { '# README' }
        base_dir.file('metadata.json') do
          JSON.dump(metadata)
        end
      end.to_io(AndFeathers::GzippedTarball)

      file.write(io.read)
      file.rewind
    end

    tarball_upload = fixture_file_upload(tarball.path, 'application/x-gzip')
    payload = options.fetch(:payload, { cookbook: "{\"category\": \"#{category.name}\"}", tarball: tarball_upload })

    signed_header = Mixlib::Authentication::SignedHeaderAuth.signing_object({
      http_method: 'post',
      path: '/api/v1/cookbooks',
      user_id: user.username,
      timestamp: Time.now.utc.iso8601,
      body: tarball.read
    }).sign(private_key)

    post '/api/v1/cookbooks', payload, signed_header
  end

  def json_body
    JSON.parse(response.body)
  end

  def signature(resource)
    resource.except('created_at', 'updated_at', 'file', 'tarball_file_size')
  end

  def error_404
    {
       'error_messages' => ['Resource does not exist'],
       'error_code' => 'NOT_FOUND'
    }
  end

  def publish_version(cookbook, version)
    create(
      :cookbook_version,
      cookbook: cookbook,
      version: version
    )
  end
end
