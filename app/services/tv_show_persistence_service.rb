class TvShowPersistenceService
  def self.persist_from_api_data(api_data)
    new.persist_from_api_data(api_data)
  end

  def persist_from_api_data(api_data)
    return { success: false, error: "No data provided" } if api_data.blank?

    stats = { processed: 0, created: 0, updated: 0, errors: [] }

    ActiveRecord::Base.transaction do
      api_data.each do |show_data|
        begin
          process_show(show_data, stats)
        rescue StandardError => e
          stats[:errors] << { show_id: show_data["id"], error: e.message }
          Rails.logger.error "Error processing show #{show_data['id']}: #{e.message}"
        end
      end
    end

    {
      success: stats[:errors].empty?,
      stats: stats
    }
  end

  private

  # Normalize show extraction for different TVMaze data formats
  # Handles episode-centric /_embedded/show, episode-centric /show, and direct show data
  def extract_show(show_data)
    show_data.dig("_embedded", "show") || show_data["show"] || show_data
  end

  def process_show(show_data, stats)
    stats[:processed] += 1

    distributor = find_or_create_distributor(show_data)
    tv_show = find_or_initialize_tv_show(show_data, distributor)

    was_new_record = tv_show.new_record?
    update_tv_show_attributes(tv_show, show_data)

    if tv_show.save!
      was_new_record ? stats[:created] += 1 : stats[:updated] += 1
      process_release_dates(tv_show, show_data)
    end
  end

  def find_or_create_distributor(show_data)
    network_name = extract_network_name(show_data)
    return Distributor.find_or_create_by!(name: "Unknown") if network_name.blank?

    Distributor.find_or_create_by!(name: network_name)
  end

  def extract_network_name(show_data)
    show = extract_show(show_data)
    show.dig("network", "name") || show.dig("webChannel", "name")
  end

  def find_or_initialize_tv_show(show_data, distributor)
    show = extract_show(show_data)
    external_id = show["id"]
    TvShow.find_or_initialize_by(external_id: external_id) do |tv_show|
      tv_show.distributor = distributor
    end
  end

  def update_tv_show_attributes(tv_show, show_data)
    show = extract_show(show_data)

    tv_show.assign_attributes(
      name: show["name"],
      show_type: show["type"],
      language: show["language"],
      status: show["status"],
      runtime: show["runtime"],
      premiered: parse_date(show["premiered"]),
      summary: clean_summary(show["summary"]),
      official_site: show["officialSite"],
      image_url: show.dig("image", "medium"),
      rating: show.dig("rating", "average")
    )
  end

  def process_release_dates(tv_show, show_data)
    country = extract_country(show_data)
    release_date = parse_date(show_data["airstamp"] || show_data["airdate"])

    return unless country && release_date

    tv_show.release_dates.find_or_create_by!(country: country) do |rd|
      rd.release_date = release_date
    end
  end

  def extract_country(show_data)
    show = extract_show(show_data)
    show.dig("network", "country", "code") ||
      show.dig("webChannel", "country", "code") ||
      "US" # Default fallback
  end

  def parse_date(date_string)
    return nil if date_string.blank?

    Date.parse(date_string)
  rescue ArgumentError
    nil
  end

  def clean_summary(summary)
    return nil if summary.blank?

    # Remove HTML tags from summary
    summary.gsub(/<[^>]*>/, "").strip
  end
end
