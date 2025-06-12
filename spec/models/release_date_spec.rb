require 'rails_helper'

RSpec.describe ReleaseDate, type: :model do
  describe 'associations' do
    it { should belong_to(:tv_show) }
  end

  describe 'validations' do
    let(:distributor) { Distributor.create!(name: 'Test Network') }
    let(:tv_show) { TvShow.create!(external_id: 1, name: 'Test Show', distributor: distributor) }
    subject { ReleaseDate.new(tv_show: tv_show, country: 'US', release_date: Date.today) }
    
    it { should validate_presence_of(:country) }
    it { should validate_presence_of(:release_date) }
    it { should validate_uniqueness_of(:country).scoped_to(:tv_show_id) }
  end
end