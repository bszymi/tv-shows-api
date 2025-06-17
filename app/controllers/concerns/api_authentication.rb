module ApiAuthentication
  extend ActiveSupport::Concern
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  included do
    before_action :authenticate_api_request
  end

  private

  def authenticate_api_request
    return if Rails.env.development? && skip_auth_in_dev?

    authenticate_or_request_with_http_basic("TV Shows API") do |username, password|
      valid_username = Rails.application.credentials.api_username || ENV.fetch("API_USERNAME", "api_user")
      valid_password = Rails.application.credentials.api_password || ENV.fetch("API_PASSWORD", "secure_password")

      ActiveSupport::SecurityUtils.secure_compare(username, valid_username) &&
        ActiveSupport::SecurityUtils.secure_compare(password, valid_password)
    end
  end

  def skip_auth_in_dev?
    params[:skip_auth] == "true"
  end

  def current_api_user
    @current_api_user ||= ApiUser.new(
      username: request.authorization&.then { |auth|
        Base64.decode64(auth.split.last).split(":").first
      },
      authenticated_at: Time.current
    )
  end

  private

  class ApiUser
    include ActiveModel::API
    include ActiveModel::Attributes

    attribute :username, :string
    attribute :authenticated_at, :datetime

    def authenticated?
      username.present? && authenticated_at.present?
    end
  end
end
