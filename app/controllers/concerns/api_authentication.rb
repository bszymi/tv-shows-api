module ApiAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_request
  end

  private

  def authenticate_api_request
    return if Rails.env.development? && skip_auth_in_dev?
    
    auth_header = request.headers['Authorization']
    
    if auth_header.present? && auth_header.start_with?('Basic ')
      # Extract credentials from Basic auth header
      encoded_credentials = auth_header.split('Basic ').last
      decoded_credentials = Base64.decode64(encoded_credentials)
      username, password = decoded_credentials.split(':', 2)
      
      # Get valid credentials
      valid_username = Rails.application.credentials.api_username || ENV['API_USERNAME'] || 'api_user'
      valid_password = Rails.application.credentials.api_password || ENV['API_PASSWORD'] || 'secure_password'
      
      # Use secure comparison to prevent timing attacks
      username_valid = ActiveSupport::SecurityUtils.secure_compare(username.to_s, valid_username)
      password_valid = ActiveSupport::SecurityUtils.secure_compare(password.to_s, valid_password)
      
      return if username_valid && password_valid
    end
    
    # Return 401 Unauthorized with WWW-Authenticate header
    response.headers['WWW-Authenticate'] = 'Basic realm="TV Shows API"'
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end

  def skip_auth_in_dev?
    # Allow skipping auth in development with a parameter
    params[:skip_auth] == 'true'
  end

  def current_api_user
    # This is a simple implementation. In a real app, you might want to:
    # - Store user information in a database
    # - Use JWT tokens
    # - Implement role-based access control
    @current_api_user ||= OpenStruct.new(
      username: request.authorization&.split(' ')&.last&.then { |token| Base64.decode64(token).split(':').first },
      authenticated_at: Time.current
    )
  end
end