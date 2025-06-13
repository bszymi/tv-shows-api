require 'rails_helper'

RSpec.describe 'API Authentication', type: :request do
  let!(:distributor) { Distributor.create!(name: 'Test Network') }
  let!(:tv_show) { TvShow.create!(external_id: 1, name: 'Test Show', distributor: distributor) }

  # Base64 encoded 'api_user:secure_password'
  let(:valid_auth_header) { "Basic #{Base64.encode64('api_user:secure_password').strip}" }
  let(:invalid_auth_header) { "Basic #{Base64.encode64('wrong:credentials').strip}" }

  describe 'with valid credentials' do
    it 'allows access to the API' do
      get '/api/v1/tv_shows', headers: { 'Authorization' => valid_auth_header }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['tv_shows']).to be_an(Array)
    end
  end

  describe 'with invalid credentials' do
    it 'returns 401 unauthorized' do
      get '/api/v1/tv_shows', headers: { 'Authorization' => invalid_auth_header }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'without credentials' do
    it 'returns 401 unauthorized' do
      get '/api/v1/tv_shows'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'in development with skip_auth parameter' do
    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
    end

    it 'allows access without authentication when skip_auth=true' do
      get '/api/v1/tv_shows', params: { skip_auth: 'true' }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['tv_shows']).to be_an(Array)
    end

    it 'still requires authentication when skip_auth is not provided' do
      get '/api/v1/tv_shows'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'WWW-Authenticate header' do
    it 'includes proper realm in unauthorized response' do
      get '/api/v1/tv_shows'

      expect(response.headers['WWW-Authenticate']).to include('Basic realm=')
    end
  end

  describe 'with environment variables' do
    around do |example|
      original_username = ENV['API_USERNAME']
      original_password = ENV['API_PASSWORD']

      ENV['API_USERNAME'] = 'env_user'
      ENV['API_PASSWORD'] = 'env_pass'

      example.run

      ENV['API_USERNAME'] = original_username
      ENV['API_PASSWORD'] = original_password
    end

    it 'uses environment variables for authentication' do
      env_auth_header = "Basic #{Base64.encode64('env_user:env_pass').strip}"

      get '/api/v1/tv_shows', headers: { 'Authorization' => env_auth_header }

      expect(response).to have_http_status(:ok)
    end
  end
end
