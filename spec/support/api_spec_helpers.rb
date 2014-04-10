require 'and_feathers'
require 'and_feathers/gzipped_tarball'
require 'tempfile'
require 'mixlib/authentication/signedheaderauth'

module ApiSpecHelpers
  class CookbookUpload
    attr_reader :tarball

    def initialize(name, options = {})
      @name = name
      @metadata = {
        name: name,
        version: '1.0.0',
        description: "Installs/Configures #{name}",
        maintainer: 'Chef Software, Inc',
        license: 'MIT',
        platforms: {
          'ubuntu' => '>= 12.0.0'
        },
        dependencies: {
          'apt' => '~> 1.0.0'
        }
      }.merge(options.fetch(:custom_metadata, {}))

      @tarball = Tempfile.new([@name, '.tgz'], 'tmp').tap do |file|
        io = AndFeathers.build(@name) do |base_dir|
          base_dir.file('README.md') { '# README' }
          base_dir.file('metadata.json') do
            JSON.dump(@metadata)
          end
        end.to_io(AndFeathers::GzippedTarball)

        file.write(io.read)
        file.rewind
      end
    end
  end

  class SignedHeader
    include FactoryGirl::Syntax::Methods

    attr_reader :contents

    def initialize(tarball, options = {})
      @tarball = tarball
      @private_key_name = options.fetch(:private_key, 'valid_private_key.pem')
      @omitted_headers = options.fetch(:omitted_headers, [])
      @request_path = options.fetch(:request_path, '/api/v1/cookbooks')
      @request_method = options.fetch(:request_method, 'post')

      if options.has_key?(:user)
        @user = options[:user]
      else
        @user = create(:user)
        @user.accounts << create(:account, provider: 'chef_oauth2')
      end

      @contents = Mixlib::Authentication::SignedHeaderAuth.signing_object({
        http_method: @request_method,
        path: @request_path,
        user_id: @user.username,
        timestamp: Time.now.utc.iso8601,
        body: @tarball.read
      }).sign(private_key)

      @omitted_headers.each { |h| @contents.delete(h) }
    end

    private

    def private_key
      OpenSSL::PKey::RSA.new(
        File.read("spec/support/key_fixtures/#{@private_key_name}")
      )
    end
  end

  def share_cookbook(cookbook_name, options = {})
    cookbook_upload = CookbookUpload.new(cookbook_name, options)
    tarball_upload = fixture_file_upload(cookbook_upload.tarball.path, 'application/x-gzip')
    signed_header = SignedHeader.new(tarball_upload, options)

    category = create(:category, name: options.fetch(:category, 'other').titleize)
    payload = options.fetch(:payload, { cookbook: "{\"category\": \"#{category.name}\"}", tarball: tarball_upload })

    post '/api/v1/cookbooks', payload, signed_header.contents
  end

  def unshare_cookbook(cookbook_name, options = {})
    cookbook_path = "/api/v1/cookbooks/#{cookbook_name}"
    cookbook_upload = CookbookUpload.new(cookbook_name, options)
    tarball_upload = fixture_file_upload(cookbook_upload.tarball.path, 'application/x-gzip')

    signed_header = SignedHeader.new(
      tarball_upload,
      request_path: cookbook_path,
      request_method: 'delete'
    )

    delete cookbook_path, { tarball: tarball_upload }, signed_header.contents
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
