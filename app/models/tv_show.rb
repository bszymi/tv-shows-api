class TvShow < ApplicationRecord
  belongs_to :distributor
  has_many :release_dates, dependent: :destroy

  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true
  validates :runtime, numericality: { greater_than: 0 }, allow_nil: true

  scope :by_distributor, ->(distributor_name) { joins(:distributor).where(distributors: { name: distributor_name }) }
  scope :by_country, ->(country) { joins(:release_dates).where(release_dates: { country: country }).distinct }
  scope :by_rating, ->(min_rating) { where('rating >= ?', min_rating) }
end