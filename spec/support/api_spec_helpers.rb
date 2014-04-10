require 'and_feathers'
require 'and_feathers/gzipped_tarball'
require 'tempfile'
require 'mixlib/authentication/signedheaderauth'

module ApiSpecHelpers
  class LocalCookbook
    # @attr_reader [Tempfile] the tarball that represents the cookbook
    attr_reader :tarball

    #
    # Initialize an example cookbook as it would appear on the local file system.
    #
    # @param [String] the name of the cookbook.
    #
    # @param [Hash] opt the options to create the cookbook with
    # @option opts [Hash] :custom_metadata any metadata that you'd like to override
    #
    def initialize(name, opts = {})
      metadata = {
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
      }.merge(opts.fetch(:custom_metadata, {}))

      @tarball = Tempfile.new([name, '.tgz'], 'tmp').tap do |file|
        io = AndFeathers.build(name) do |base_dir|
          base_dir.file('README.md') { '# README' }
          base_dir.file('metadata.json') do
            JSON.dump(metadata)
          end
        end.to_io(AndFeathers::GzippedTarball)

        file.write(io.read)
        file.rewind
      end
    end
  end

  class SignedHeader
    include FactoryGirl::Syntax::Methods

    # @attr_reader [Hash] the contents of the signed header to be used with the request
    attr_reader :contents

    #
    # Create a SignedHeader used for authenticated API requests
    #
    # @param [tarball] the file to sign the headers with, used for the content hash portion
    #
    # @param [Hash] opts the options to generate the signed header with
    #
    # @option opts [String] :private_key the name of the private key to generate the headers with
    # @option opts [Array] :omitted_headers any signed headers you wish to omitt
    # @option opts [String] :request_path the path of the request to be made
    # @option opts [String] :request_method the HTTP method of the request to be made
    # @option opts [User] :user the user that will be making the request
    #
    def initialize(tarball, opts = {})
      private_key = OpenSSL::PKey::RSA.new(
        File.read("spec/support/key_fixtures/#{opts.fetch(:private_key, 'valid_private_key.pem')}")
      )

      if opts.has_key?(:user)
        user = opts[:user]
      else
        user = create(:user)
        user.accounts << create(:account, provider: 'chef_oauth2')
      end

      @contents = Mixlib::Authentication::SignedHeaderAuth.signing_object({
        http_method: opts.fetch(:request_method, 'post'),
        path: opts.fetch(:request_path, '/api/v1/cookbooks'),
        user_id: user.username,
        timestamp: Time.now.utc.iso8601,
        body: tarball.read
      }).sign(private_key)

      opts.fetch(:omitted_headers, []).each { |h| @contents.delete(h) }
    end
  end

  def share_cookbook(cookbook_name, options = {})
    cookbook_upload = LocalCookbook.new(cookbook_name, options)
    tarball_upload = fixture_file_upload(cookbook_upload.tarball.path, 'application/x-gzip')
    signed_header = SignedHeader.new(tarball_upload, options)

    category = create(:category, name: options.fetch(:category, 'other').titleize)
    payload = options.fetch(:payload, { cookbook: "{\"category\": \"#{category.name}\"}", tarball: tarball_upload })

    post '/api/v1/cookbooks', payload, signed_header.contents
  end

  def unshare_cookbook(cookbook_name, options = {})
    cookbook_path = "/api/v1/cookbooks/#{cookbook_name}"
    cookbook_upload = LocalCookbook.new(cookbook_name, options)
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
