class CreateDistributors < ActiveRecord::Migration[8.0]
  def change
    create_table :distributors do |t|
      t.string :name

      t.timestamps
    end
    add_index :distributors, :name, unique: true
  end
end
