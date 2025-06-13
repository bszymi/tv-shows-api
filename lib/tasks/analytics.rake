namespace :analytics do
  desc "Run analytical queries to demonstrate database capabilities"
  task run_examples: :environment do
    puts "=== TV Shows Analytics Examples ==="
    puts

    # Example 1: Top distributors by average rating
    puts "1. Top 5 distributors by average rating (shows with ratings only):"
    top_distributors = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT#{' '}
        d.name as distributor_name,
        COUNT(t.id) as total_shows,
        AVG(t.rating) as avg_rating,
        MIN(t.rating) as min_rating,
        MAX(t.rating) as max_rating
      FROM distributors d
      JOIN tv_shows t ON d.id = t.distributor_id
      WHERE t.rating IS NOT NULL
      GROUP BY d.id, d.name
      HAVING COUNT(t.id) >= 3
      ORDER BY avg_rating DESC
      LIMIT 5;
    SQL

    top_distributors.each do |row|
      puts "   #{row['distributor_name']}: #{row['total_shows']} shows, avg: #{row['avg_rating'].to_f.round(2)}"
    end
    puts

    # Example 2: Shows by decade with window functions
    puts "2. Show count by decade with running totals:"
    by_decade = ActiveRecord::Base.connection.execute(<<~SQL)
      WITH decade_stats AS (
        SELECT#{' '}
          EXTRACT(DECADE FROM premiered) * 10 as decade,
          COUNT(*) as show_count
        FROM tv_shows#{' '}
        WHERE premiered IS NOT NULL
        GROUP BY EXTRACT(DECADE FROM premiered)
      )
      SELECT#{' '}
        decade,
        show_count,
        SUM(show_count) OVER (ORDER BY decade ROWS UNBOUNDED PRECEDING) as running_total,
        ROUND(
          CAST(100.0 * show_count / SUM(show_count) OVER () AS NUMERIC), 2
        ) as percentage
      FROM decade_stats
      ORDER BY decade;
    SQL

    by_decade.each do |row|
      puts "   #{row['decade']}s: #{row['show_count']} shows (#{row['percentage']}%), running total: #{row['running_total']}"
    end
    puts

    # Example 3: Country release patterns with CTEs
    puts "3. Countries with most international show releases:"
    country_stats = ActiveRecord::Base.connection.execute(<<~SQL)
      WITH country_rankings AS (
        SELECT#{' '}
          rd.country,
          COUNT(DISTINCT rd.tv_show_id) as unique_shows,
          COUNT(*) as total_releases,
          ROUND(CAST(AVG(ts.rating) FILTER (WHERE ts.rating IS NOT NULL) AS NUMERIC), 2) as avg_rating
        FROM release_dates rd
        JOIN tv_shows ts ON rd.tv_show_id = ts.id
        GROUP BY rd.country
      ),
      country_percentiles AS (
        SELECT#{' '}
          *,
          PERCENT_RANK() OVER (ORDER BY unique_shows) as percentile_rank
        FROM country_rankings
      )
      SELECT#{' '}
        country,
        unique_shows,
        total_releases,
        ROUND(avg_rating, 2) as avg_rating,
        ROUND(CAST(percentile_rank * 100 AS NUMERIC), 1) as percentile
      FROM country_percentiles
      WHERE unique_shows >= 5
      ORDER BY unique_shows DESC
      LIMIT 10;
    SQL

    country_stats.each do |row|
      puts "   #{row['country']}: #{row['unique_shows']} shows, avg rating: #{row['avg_rating'] || 'N/A'}"
    end
    puts

    # Example 4: Status distribution with aggregation
    puts "4. Show status distribution:"
    status_dist = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT#{' '}
        COALESCE(status, 'Unknown') as status,
        COUNT(*) as count,
        ROUND(CAST(AVG(rating) AS NUMERIC), 2) as avg_rating,
        ROUND(CAST(AVG(runtime) AS NUMERIC), 0) as avg_runtime
      FROM tv_shows
      GROUP BY status
      ORDER BY count DESC;
    SQL

    status_dist.each do |row|
      puts "   #{row['status']}: #{row['count']} shows, avg rating: #{row['avg_rating'] || 'N/A'}, avg runtime: #{row['avg_runtime'] || 'N/A'}min"
    end
    puts

    # Example 5: Complex query with multiple joins and window functions
    puts "5. Top rated shows per distributor (with rankings):"
    top_per_distributor = ActiveRecord::Base.connection.execute(<<~SQL)
      WITH ranked_shows AS (
        SELECT#{' '}
          ts.name as show_name,
          ts.rating,
          d.name as distributor_name,
          ts.premiered,
          ROW_NUMBER() OVER (PARTITION BY d.id ORDER BY ts.rating DESC, ts.name) as rank
        FROM tv_shows ts
        JOIN distributors d ON ts.distributor_id = d.id
        WHERE ts.rating IS NOT NULL
      )
      SELECT#{' '}
        distributor_name,
        show_name,
        rating,
        premiered
      FROM ranked_shows
      WHERE rank <= 2
      ORDER BY distributor_name, rank;
    SQL

    current_distributor = nil
    top_per_distributor.each do |row|
      if row["distributor_name"] != current_distributor
        puts "   #{row['distributor_name']}:" if current_distributor
        current_distributor = row["distributor_name"]
        puts "   #{current_distributor}:"
      end
      puts "     - #{row['show_name']} (#{row['rating']}) - #{row['premiered']}"
    end

    puts
    puts "=== Analytics Complete ==="
  end

  desc "Generate sample data for analytics testing"
  task generate_sample_data: :environment do
    puts "Generating sample data for analytics..."

    # Create sample distributors
    distributors = %w[HBO Netflix CBS NBC FOX ABC CW Hulu Amazon Disney+].map do |name|
      Distributor.find_or_create_by(name: name)
    end

    # Create sample shows with varied data
    100.times do |i|
      show = TvShow.create!(
        external_id: 10000 + i,
        name: "Sample Show #{i + 1}",
        show_type: %w[Scripted Reality Documentary Animation].sample,
        language: %w[English Spanish French German Japanese].sample,
        status: %w[Running Ended Cancelled].sample,
        runtime: [ 30, 45, 60, 90 ].sample,
        premiered: Date.parse("#{rand(1990..2023)}-#{rand(1..12)}-#{rand(1..28)}"),
        rating: rand(1.0..10.0).round(1),
        distributor: distributors.sample
      )

      # Add release dates for some countries
      %w[US UK CA AU DE FR ES JP].sample(rand(1..3)).each do |country|
        ReleaseDate.create!(
          tv_show: show,
          country: country,
          release_date: show.premiered + rand(0..365).days
        )
      end
    end

    puts "Generated 100 sample shows with release dates."
  end
end
