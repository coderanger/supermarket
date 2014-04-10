require 'and_feathers'
require 'and_feathers/gzipped_tarball'
require 'tempfile'
require 'mixlib/authentication/signedheaderauth'

module ApiSpecHelpers
  def share_cookbook(cookbook_name, opts = {})
    tarball = cookbook_upload(cookbook_name, opts)
    header = signed_header(tarball, opts)

    category = create(:category, name: opts.fetch(:category, 'other').titleize)
    payload = opts.fetch(:payload, cookbook: "{\"category\": \"#{category.name}\"}", tarball: tarball)

    post '/api/v1/cookbooks', payload, header
  end

  def unshare_cookbook(cookbook_name, opts = {})
    cookbook_path = "/api/v1/cookbooks/#{cookbook_name}"

    tarball = cookbook_upload(cookbook_name, opts)
    header = signed_header(tarball, request_path: cookbook_path, request_method: 'delete')

    delete cookbook_path, { tarball: tarball }, header
  end

  def signed_header(tarball, opts = {})
    private_key = OpenSSL::PKey::RSA.new(
      File.read("spec/support/key_fixtures/#{opts.fetch(:private_key, 'valid_private_key.pem')}")
    )

    if opts.key?(:user)
      user = opts[:user]
    else
      user = create(:user)
      user.accounts << create(:account, provider: 'chef_oauth2')
    end

    contents = Mixlib::Authentication::SignedHeaderAuth.signing_object(
      http_method: opts.fetch(:request_method, 'post'),
      path: opts.fetch(:request_path, '/api/v1/cookbooks'),
      user_id: user.username,
      timestamp: Time.now.utc.iso8601,
      body: tarball.read
    ).sign(private_key)

    opts.fetch(:omitted_headers, []).each { |h| contents.delete(h) }

    contents
  end

  def cookbook_upload(cookbook_name, opts = {})
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
    }.merge(opts.fetch(:custom_metadata, {}))

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

    fixture_file_upload(tarball.path, 'application/x-gzip')
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
