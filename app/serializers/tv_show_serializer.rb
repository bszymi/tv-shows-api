class TvShowSerializer < ActiveModel::Serializer
  attributes :id, :external_id, :name, :show_type, :language, :status, 
             :runtime, :premiered, :summary, :official_site, :image_url, :rating

  belongs_to :distributor
  has_many :release_dates

  def premiered
    object.premiered&.iso8601
  end
end