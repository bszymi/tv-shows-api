require 'rails_helper'

RSpec.describe TvShow, type: :model do
  describe 'associations' do
    it { should belong_to(:distributor) }
    it { should have_many(:release_dates).dependent(:destroy) }
  end

  describe 'validations' do
    let(:distributor) { Distributor.create!(name: 'Test Network') }
    subject { TvShow.new(external_id: 1, name: 'Test Show', distributor: distributor) }
    
    it { should validate_presence_of(:external_id) }
    it { should validate_uniqueness_of(:external_id) }
    it { should validate_presence_of(:name) }
    it { should validate_numericality_of(:rating).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(10).allow_nil }
    it { should validate_numericality_of(:runtime).is_greater_than(0).allow_nil }
  end

  describe 'scopes' do
    let!(:distributor1) { Distributor.create!(name: 'Network One') }
    let!(:distributor2) { Distributor.create!(name: 'Network Two') }
    let!(:show1) { TvShow.create!(external_id: 1, name: 'Show 1', distributor: distributor1, rating: 8.5) }
    let!(:show2) { TvShow.create!(external_id: 2, name: 'Show 2', distributor: distributor2, rating: 7.0) }
    let!(:release_date1) { ReleaseDate.create!(tv_show: show1, country: 'US', release_date: Date.today) }
    let!(:release_date2) { ReleaseDate.create!(tv_show: show2, country: 'UK', release_date: Date.today) }

    describe '.by_distributor' do
      it 'returns shows for the specified distributor' do
        expect(TvShow.by_distributor('Network One')).to eq([show1])
      end
    end

    describe '.by_country' do
      it 'returns shows for the specified country' do
        expect(TvShow.by_country('US')).to eq([show1])
      end
    end

    describe '.by_rating' do
      it 'returns shows with rating greater than or equal to specified value' do
        expect(TvShow.by_rating(8.0)).to eq([show1])
      end
    end
  end
end