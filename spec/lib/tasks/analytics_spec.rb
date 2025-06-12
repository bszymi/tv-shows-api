require 'rails_helper'
require 'rake'

RSpec.describe 'analytics:run_examples', type: :task do
  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let!(:distributor1) { Distributor.create!(name: 'HBO') }
  let!(:distributor2) { Distributor.create!(name: 'Netflix') }
  
  let!(:show1) do
    TvShow.create!(
      external_id: 1001,
      name: 'Test Show 1',
      rating: 8.5,
      premiered: Date.parse('2020-01-01'),
      status: 'Running',
      runtime: 60,
      distributor: distributor1
    )
  end
  
  let!(:show2) do
    TvShow.create!(
      external_id: 1002,
      name: 'Test Show 2',
      rating: 7.8,
      premiered: Date.parse('2019-06-15'),
      status: 'Ended',
      runtime: 45,
      distributor: distributor2
    )
  end

  let!(:release_date1) { ReleaseDate.create!(tv_show: show1, country: 'US', release_date: Date.parse('2020-01-01')) }
  let!(:release_date2) { ReleaseDate.create!(tv_show: show2, country: 'UK', release_date: Date.parse('2019-06-15')) }

  it 'runs without errors' do
    expect { Rake::Task['analytics:run_examples'].invoke }.not_to raise_error
  end

  it 'can execute analytical queries' do
    # Test that the complex SQL queries don't fail
    expect do
      # Top distributors query
      ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT 
          d.name as distributor_name,
          COUNT(t.id) as total_shows,
          AVG(t.rating) as avg_rating
        FROM distributors d
        JOIN tv_shows t ON d.id = t.distributor_id
        WHERE t.rating IS NOT NULL
        GROUP BY d.id, d.name
        ORDER BY avg_rating DESC
        LIMIT 5;
      SQL
    end.not_to raise_error

    expect do
      # Decade stats with window functions
      ActiveRecord::Base.connection.execute(<<~SQL)
        WITH decade_stats AS (
          SELECT 
            EXTRACT(DECADE FROM premiered) * 10 as decade,
            COUNT(*) as show_count
          FROM tv_shows 
          WHERE premiered IS NOT NULL
          GROUP BY EXTRACT(DECADE FROM premiered)
        )
        SELECT 
          decade,
          show_count,
          SUM(show_count) OVER (ORDER BY decade ROWS UNBOUNDED PRECEDING) as running_total
        FROM decade_stats
        ORDER BY decade;
      SQL
    end.not_to raise_error
  end
end

RSpec.describe 'analytics:generate_sample_data', type: :task do
  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  it 'generates sample data successfully' do
    expect { Rake::Task['analytics:generate_sample_data'].invoke }.to change(TvShow, :count).by(100)
      .and change(Distributor, :count).by_at_least(1)
      .and change(ReleaseDate, :count).by_at_least(100)
  end
end