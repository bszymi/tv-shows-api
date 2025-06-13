require 'net/http'
require 'json'
require 'digest'

class TvMazeApiService
  API_URL = 'https://api.tvmaze.com/schedule/full'.freeze
  TIMEOUT = 30

  def self.fetch_full_schedule(force_full_refresh: false)
    new.fetch_full_schedule(force_full_refresh: force_full_refresh)
  end

  def fetch_full_schedule(force_full_refresh: false)
    Rails.logger.info "Starting TVMaze data fetch (force_full_refresh: #{force_full_refresh})"
    
    # Fetch new data from API
    new_data_result = fetch_api_data
    return new_data_result unless new_data_result[:success]
    
    new_data = new_data_result[:data]
    
    # Handle incremental processing
    if force_full_refresh || !TvMazeDataStorage.data_exists?
      Rails.logger.info "Processing full dataset (#{new_data.size} records)"
      process_full_dataset(new_data)
    else
      Rails.logger.info "Checking for incremental changes"
      process_incremental_changes(new_data)
    end
  rescue StandardError => e
    Rails.logger.error "TVMaze API Service Error: #{e.message}"
    { success: false, error: e.message, data: [] }
  end

  private

  def fetch_api_data
    uri = URI(API_URL)
    response = perform_request(uri)
    
    case response
    when Net::HTTPSuccess
      parse_response(response.body)
    else
      handle_error_response(response)
    end
  rescue StandardError => e
    Rails.logger.error "TVMaze API fetch error: #{e.message}"
    { success: false, error: e.message, data: [] }
  end

  def process_full_dataset(new_data)
    result = { success: true, data: new_data, count: new_data.size }
    
    # Store the new data
    if TvMazeDataStorage.write_data(new_data)
      Rails.logger.info "Stored #{new_data.size} records to storage"
      result[:storage_updated] = true
    else
      Rails.logger.warn "Failed to store data to storage"
      result[:storage_updated] = false
    end
    
    result
  end

  def process_incremental_changes(new_data)
    previous_data = TvMazeDataStorage.read_data
    
    if previous_data.nil?
      Rails.logger.warn "Previous data could not be read, falling back to full processing"
      return process_full_dataset(new_data)
    end
    
    # Calculate hashes to check for overall changes
    new_hash = calculate_data_hash(new_data)
    previous_hash = calculate_data_hash(previous_data)
    
    if new_hash == previous_hash
      Rails.logger.info "No changes detected in data"
      return { success: true, data: [], count: 0, changes: 0, skipped: new_data.size }
    end
    
    Rails.logger.info "Data changes detected, finding differences"
    
    # Find specific changes
    changes = find_data_changes(previous_data, new_data)
    
    result = {
      success: true,
      data: changes,
      count: changes.size,
      changes: changes.size,
      examined: new_data.size
    }
    
    # Store the new data if there were changes
    if TvMazeDataStorage.write_data(new_data)
      Rails.logger.info "Updated storage with #{new_data.size} records (#{changes.size} changes)"
      result[:storage_updated] = true
    else
      Rails.logger.warn "Failed to update storage"
      result[:storage_updated] = false
    end
    
    result
  end

  def calculate_data_hash(data)
    # Sort data by show ID to ensure consistent hashing
    sorted_data = data.sort_by { |item| [item.dig('show', 'id') || item['id'] || 0, item['id'] || 0] }
    Digest::SHA256.hexdigest(JSON.generate(sorted_data))
  end

  def find_data_changes(previous_data, new_data)
    # Create lookup maps for efficient comparison
    previous_map = create_episode_lookup_map(previous_data)
    new_map = create_episode_lookup_map(new_data)
    
    changes = []
    
    # Check for new or changed episodes
    new_map.each do |key, new_episode|
      previous_episode = previous_map[key]
      
      if previous_episode.nil?
        # New episode
        changes << new_episode
        Rails.logger.debug "New episode detected: #{key}"
      elsif calculate_episode_hash(previous_episode) != calculate_episode_hash(new_episode)
        # Changed episode
        changes << new_episode
        Rails.logger.debug "Changed episode detected: #{key}"
      end
    end
    
    Rails.logger.info "Found #{changes.size} changed episodes out of #{new_data.size} total"
    changes
  end

  def create_episode_lookup_map(data)
    data.each_with_object({}) do |episode, map|
      # Create a unique key for each episode
      show_id = episode.dig('show', 'id') || episode['id']
      episode_id = episode['id']
      airdate = episode['airdate']
      
      # Use a combination of show_id, episode_id, and airdate as the key
      key = "#{show_id}_#{episode_id}_#{airdate}"
      map[key] = episode
    end
  end

  def calculate_episode_hash(episode)
    # Create a normalized hash of episode data for comparison
    normalized = {
      id: episode['id'],
      show: episode['show'],
      airdate: episode['airdate'],
      airstamp: episode['airstamp']
    }
    Digest::MD5.hexdigest(JSON.generate(normalized))
  end

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
      { success: false, error: 'Unexpected response format', data: [] }
    end
  rescue JSON::ParserError => e
    Rails.logger.error "JSON Parse Error: #{e.message}"
    { success: false, error: 'Invalid JSON response', data: [] }
  end

  def handle_error_response(response)
    error_message = "HTTP #{response.code}: #{response.message}"
    Rails.logger.error "TVMaze API Error: #{error_message}"
    { success: false, error: error_message, data: [] }
  end
end