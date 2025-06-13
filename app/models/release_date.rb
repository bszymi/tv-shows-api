class ReleaseDate < ApplicationRecord
  belongs_to :tv_show

  validates :country, presence: true
  validates :release_date, presence: true
  validates :country, uniqueness: { scope: :tv_show_id }
end
