class CreateReleaseDates < ActiveRecord::Migration[8.0]
  def change
    create_table :release_dates do |t|
      t.references :tv_show, null: false, foreign_key: true
      t.string :country
      t.date :release_date

      t.timestamps
    end
    add_index :release_dates, :country
    add_index :release_dates, :release_date
    add_index :release_dates, [ :tv_show_id, :country ], unique: true
  end
end
