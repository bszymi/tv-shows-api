class ReleaseDateSerializer < ActiveModel::Serializer
  attributes :id, :country, :release_date

  def release_date
    object.release_date&.iso8601
  end
end