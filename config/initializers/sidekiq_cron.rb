Rails.application.config.after_initialize do
  if Sidekiq.server?
    # Schedule the TV shows sync job to run daily at 2 AM UTC
    Sidekiq::Cron::Job.load_from_hash({
      'tv_shows_daily_sync' => {
        'cron' => '0 2 * * *',
        'class' => 'TvShowsSyncWorker',
        'description' => 'Daily sync of TV shows data from TVMaze API'
      }
    })
  end
end