class AddPerformanceIndicesToTables < ActiveRecord::Migration[8.0]
  def change
    # Indices for common query patterns
    add_index :tv_shows, :rating, where: 'rating IS NOT NULL'
    add_index :tv_shows, :status
    add_index :tv_shows, :language
    add_index :tv_shows, :premiered
    add_index :tv_shows, [ :status, :rating ], where: 'rating IS NOT NULL'
    add_index :tv_shows, [ :distributor_id, :rating ], where: 'rating IS NOT NULL'

    # Composite index for filtering by distributor and country
    add_index :release_dates, [ :country, :release_date ]

    # Regular btree index for name searches (GIN trigram would require pg_trgm extension)
    add_index :tv_shows, :name
  end
end
