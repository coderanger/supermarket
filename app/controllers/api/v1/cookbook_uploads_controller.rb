require 'cookbook_upload'
require 'mixlib/authentication/signatureverification'

class Api::V1::CookbookUploadsController < Api::V1Controller
  #
  # POST /api/v1/cookbooks
  #
  # Accepts cookbooks to share. A sharing request is a multipart POST. Two of
  # those parts are relevant to this method: +cookbook+ and +tarball+.
  #
  # The +cookbook+ part is a serialized JSON object which must contain a
  # +"category"+ key. The value of this key is the name of the category to
  # which this cookbook belongs.
  #
  # The +tarball+ part is a gzipped tarball containing the cookbook. Crucially,
  # this tarball must contain a +metadata.json+ entry, which is typically
  # generated by knife, and derived from the cookbook's +metadata.rb+.
  #
  # There are two use cases for sharing a cookbook: adding a new cookbook to
  # the community site, and updating an existing cookbook. Both are handled by
  # this action.
  #
  # There are also several failure modes for sharing a cookbook. These include,
  # but are not limited to, forgetting to specify a category, specifying a
  # non-existent category, forgetting to upload a tarball, uploading a tarball
  # without a metadata.json entry, and so forth.
  #
  # The majority of the work happens between +CookbookUpload+,
  # +CookbookUpload::Parameters+, and +Cookbook+
  #
  # @see Cookbook
  # @see CookbookUpload
  # @see CookbookUpload::Parameters
  #
  def create
    authenticate_user!
    cookbook_upload = CookbookUpload.new(upload_params)
    cookbook_upload.finish do |errors, cookbook|
      if errors.any?
        error(
          error: t('api.error_codes.invalid_data'),
          error_messages: errors.full_messages
        )
      else
        @cookbook = cookbook

        SegmentIO.track_server_event(
          'cookbook_version_published',
          cookbook: @cookbook.name
        )

        render :create, status: 201
      end
    end
  end

  rescue_from ActionController::ParameterMissing do |e|
    error(
      error_code: t('api.error_codes.invalid_data'),
      error_messages: t("api.error_messages.missing_#{e.param}")
    )
  end

  private

  def error(body) render json: body, status: 400 end
  #
  # The parameters required to upload a cookbook
  #
  # @raise [ActionController::ParameterMissing] if the +:cookbook+ parameter is
  #   missing
  # @raise [ActionController::ParameterMissing] if the +:tarball+ parameter is
  #   missing
  #
  def upload_params
    {
      cookbook: params.require(:cookbook),
      tarball: params.require(:tarball)
    }
  end

  #
  # Finds a user specified in the request header or renders an error if
  # the user doesn't exist. Then attempts to authorize the signed request
  # against the users public key or renders an error if it fails.
  #
  def authenticate_user!
    username = request.headers['X-Ops-Userid']
    user = User.joins(:accounts).
      where('accounts.username = ? AND accounts.provider = ?', username, 'chef_oauth2').first

    if !user
      error(
        error: t('api.error_codes.authentication_failed'),
        error_messages: t("api.error_messages.invalid_username", username: username)
      )
    end

    begin
      Mixlib::Authentication::SignatureVerification.new.authenticate_user_request(
        request,
        OpenSSL::PKey::RSA.new(user.public_key)
      )
    rescue StandardError => e
      error(
        error: t('api.error_codes.authentication_failed'),
        error_messages: e
      )
    end
  end
end
