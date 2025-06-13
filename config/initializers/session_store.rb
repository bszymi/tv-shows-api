# Session middleware configuration for Sidekiq Web UI
# Since this is an API-only Rails application, we only enable session support
# in development and test environments to access the Sidekiq Web UI.
# In production, consider using proper authentication and authorization.

if Rails.env.development? || Rails.env.test?
  Rails.application.config.session_store :cookie_store, key: "_tv_shows_api_session"
  Rails.application.config.middleware.use ActionDispatch::Cookies
  Rails.application.config.middleware.use ActionDispatch::Session::CookieStore, Rails.application.config.session_options
end
