class Api::V1::TvShowsController < ApplicationController
  include ApiAuthentication
  def index
    @tv_shows = TvShow.includes(:distributor, :release_dates)
                     .order(:name, :id) # Deterministic ordering
    
    @tv_shows = apply_filters(@tv_shows)
    @tv_shows = @tv_shows.page(params[:page]).per(params[:per_page] || 25)
    
    render json: {
      tv_shows: ActiveModel::Serializer::CollectionSerializer.new(@tv_shows, serializer: TvShowSerializer),
      meta: pagination_meta(@tv_shows)
    }
  end

  private

  def apply_filters(tv_shows)
    tv_shows = tv_shows.by_distributor(params[:distributor]) if params[:distributor].present?
    tv_shows = tv_shows.by_country(params[:country]) if params[:country].present?
    tv_shows = tv_shows.by_rating(params[:min_rating]) if params[:min_rating].present?
    tv_shows
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: collection.limit_value
    }
  end
end