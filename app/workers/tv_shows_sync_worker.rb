class TvShowsSyncWorker
  include Sidekiq::Worker
  
  sidekiq_options retry: 3, dead: false

  def perform
    Rails.logger.info "Starting TV shows sync job"
    
    # Fetch data from TVMaze API
    api_response = TvMazeApiService.fetch_full_schedule
    
    if api_response[:success]
      Rails.logger.info "Fetched #{api_response[:count]} shows from TVMaze API"
      
      # Persist the data
      persistence_result = TvShowPersistenceService.persist_from_api_data(api_response[:data])
      
      if persistence_result[:success]
        stats = persistence_result[:stats]
        Rails.logger.info "TV shows sync completed successfully: #{stats[:processed]} processed, #{stats[:created]} created, #{stats[:updated]} updated"
      else
        stats = persistence_result[:stats]
        Rails.logger.error "TV shows sync completed with errors: #{stats[:errors].size} errors out of #{stats[:processed]} processed"
        stats[:errors].each do |error|
          Rails.logger.error "Show ID #{error[:show_id]}: #{error[:error]}"
        end
      end
    else
      Rails.logger.error "Failed to fetch TV shows data: #{api_response[:error]}"
      raise "API fetch failed: #{api_response[:error]}"
    end
  rescue StandardError => e
    Rails.logger.error "TV shows sync job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end