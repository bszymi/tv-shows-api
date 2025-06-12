require 'net/http'
require 'json'

class TvMazeApiService
  API_URL = 'https://api.tvmaze.com/schedule/full'.freeze
  TIMEOUT = 30

  def self.fetch_full_schedule
    new.fetch_full_schedule
  end

  def fetch_full_schedule
    uri = URI(API_URL)
    response = perform_request(uri)
    
    case response
    when Net::HTTPSuccess
      parse_response(response.body)
    else
      handle_error_response(response)
    end
  rescue StandardError => e
    Rails.logger.error "TVMaze API Service Error: #{e.message}"
    { error: e.message, data: [] }
  end

  private

  def perform_request(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = TIMEOUT
    http.open_timeout = TIMEOUT
    
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'TV Shows API/1.0'
    
    http.request(request)
  end

  def parse_response(response_body)
    data = JSON.parse(response_body)
    
    if data.is_a?(Array)
      { success: true, data: data, count: data.size }
    else
      { error: 'Unexpected response format', data: [] }
    end
  rescue JSON::ParserError => e
    Rails.logger.error "JSON Parse Error: #{e.message}"
    { error: 'Invalid JSON response', data: [] }
  end

  def handle_error_response(response)
    error_message = "HTTP #{response.code}: #{response.message}"
    Rails.logger.error "TVMaze API Error: #{error_message}"
    { error: error_message, data: [] }
  end
end