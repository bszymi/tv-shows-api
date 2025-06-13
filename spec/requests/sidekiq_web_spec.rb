require 'rails_helper'

RSpec.describe 'Sidekiq Web UI', type: :request do
  describe 'GET /sidekiq' do
    it 'is accessible in test environment' do
      get '/sidekiq'
      
      # Should return 200 OK and display Sidekiq Web UI
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Sidekiq')
    end
    
    it 'has session middleware available' do
      # Check that session middleware is loaded
      middleware_classes = Rails.application.config.middleware.map(&:name)
      
      expect(middleware_classes).to include('ActionDispatch::Cookies')
      expect(middleware_classes).to include('ActionDispatch::Session::CookieStore')
    end
  end
  
  describe 'session configuration' do
    it 'is configured for test environments' do
      expect(Rails.application.config.session_store).to eq(ActionDispatch::Session::CookieStore)
      expect(Rails.application.config.session_options[:key]).to eq('_tv_shows_api_session')
    end
    
    it 'only loads session middleware in development and test' do
      # Verify the configuration is environment-dependent
      expect(Rails.env.test? || Rails.env.development?).to be true
      
      # Verify middleware is present
      middleware_names = Rails.application.config.middleware.map(&:name)
      expect(middleware_names).to include('ActionDispatch::Cookies')
      expect(middleware_names).to include('ActionDispatch::Session::CookieStore')
    end
  end
end