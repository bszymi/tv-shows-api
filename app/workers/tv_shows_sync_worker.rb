class TvShowsSyncWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: false

  def perform(force_full_refresh: false)
    Rails.logger.info "Starting TV shows sync job (incremental: #{!force_full_refresh})"

    # Fetch data from TVMaze API with incremental processing
    api_response = TvMazeApiService.fetch_full_schedule(force_full_refresh: force_full_refresh)

    if api_response[:success]
      data_to_process = api_response[:data]

      if api_response[:skipped]
        Rails.logger.info "No changes detected - #{api_response[:skipped]} records skipped"
        return
      elsif data_to_process.empty?
        Rails.logger.info "No new or changed data to process"
        return
      end

      Rails.logger.info "Processing #{data_to_process.size} records (#{api_response[:changes] || data_to_process.size} changes)"

      # Persist the data (only changed/new records)
      persistence_result = TvShowPersistenceService.persist_from_api_data(data_to_process)

      if persistence_result[:success]
        stats = persistence_result[:stats]
        Rails.logger.info "TV shows sync completed successfully: #{stats[:processed]} processed, #{stats[:created]} created, #{stats[:updated]} updated"

        if api_response[:changes]
          Rails.logger.info "Incremental processing: #{api_response[:changes]} changes out of #{api_response[:examined]} examined"
        end
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
