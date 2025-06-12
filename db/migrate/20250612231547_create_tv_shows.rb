class CreateTvShows < ActiveRecord::Migration[8.0]
  def change
    create_table :tv_shows do |t|
      t.integer :external_id
      t.string :name
      t.string :show_type
      t.string :language
      t.string :status
      t.integer :runtime
      t.date :premiered
      t.text :summary
      t.string :official_site
      t.string :image_url
      t.decimal :rating, precision: 3, scale: 1
      t.references :distributor, null: false, foreign_key: true

      t.timestamps
    end
    add_index :tv_shows, :external_id, unique: true
  end
end
