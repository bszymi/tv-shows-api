require 'rails_helper'

RSpec.describe TvShowPersistenceService, type: :service do
  describe '.persist_from_api_data' do
    subject { described_class.persist_from_api_data(api_data) }

    context 'when no data is provided' do
      let(:api_data) { [] }

      it 'returns error response' do
        expect(subject).to include(
          success: false,
          error: 'No data provided'
        )
      end
    end

    context 'when valid API data is provided' do
      let(:api_data) do
        [
          {
            'id' => 1,
            'name' => 'Under the Dome',
            'type' => 'Scripted',
            'language' => 'English',
            'status' => 'Ended',
            'runtime' => 60,
            'premiered' => '2013-06-24',
            'summary' => '<p>Under the Dome is the story of a small town.</p>',
            'officialSite' => 'http://www.cbs.com/shows/under-the-dome/',
            'image' => { 'medium' => 'http://static.tvmaze.com/uploads/images/medium_portrait/0/1.jpg' },
            'rating' => { 'average' => 6.5 },
            'network' => { 
              'name' => 'CBS',
              'country' => { 'code' => 'US' }
            },
            'airstamp' => '2013-06-24T22:00:00+00:00'
          }
        ]
      end

      it 'creates new TV show with distributor and release date' do
        expect { subject }.to change(TvShow, :count).by(1)
                          .and change(Distributor, :count).by(1)
                          .and change(ReleaseDate, :count).by(1)
      end

      it 'returns success response with stats' do
        result = subject
        expect(result[:success]).to be true
        expect(result[:stats]).to include(
          processed: 1,
          created: 1,
          updated: 0,
          errors: []
        )
      end

      it 'stores TV show attributes correctly' do
        subject
        tv_show = TvShow.first
        
        expect(tv_show.external_id).to eq(1)
        expect(tv_show.name).to eq('Under the Dome')
        expect(tv_show.show_type).to eq('Scripted')
        expect(tv_show.language).to eq('English')
        expect(tv_show.status).to eq('Ended')
        expect(tv_show.runtime).to eq(60)
        expect(tv_show.premiered).to eq(Date.parse('2013-06-24'))
        expect(tv_show.summary).to eq('Under the Dome is the story of a small town.')
        expect(tv_show.official_site).to eq('http://www.cbs.com/shows/under-the-dome/')
        expect(tv_show.image_url).to eq('http://static.tvmaze.com/uploads/images/medium_portrait/0/1.jpg')
        expect(tv_show.rating).to eq(6.5)
      end

      it 'creates distributor correctly' do
        subject
        distributor = Distributor.first
        expect(distributor.name).to eq('CBS')
      end

      it 'creates release date correctly' do
        subject
        release_date = ReleaseDate.first
        expect(release_date.country).to eq('US')
        expect(release_date.release_date).to eq(Date.parse('2013-06-24'))
      end
    end

    context 'when updating existing TV show' do
      let!(:distributor) { Distributor.create!(name: 'CBS') }
      let!(:existing_show) do
        TvShow.create!(
          external_id: 1,
          name: 'Old Name',
          distributor: distributor,
          rating: 5.0
        )
      end

      let(:api_data) do
        [
          {
            'id' => 1,
            'name' => 'Updated Name',
            'type' => 'Scripted',
            'rating' => { 'average' => 8.5 },
            'network' => { 
              'name' => 'CBS',
              'country' => { 'code' => 'US' }
            }
          }
        ]
      end

      it 'updates existing TV show' do
        expect { subject }.not_to change(TvShow, :count)
        
        existing_show.reload
        expect(existing_show.name).to eq('Updated Name')
        expect(existing_show.rating).to eq(8.5)
      end

      it 'returns correct stats' do
        result = subject
        expect(result[:stats]).to include(
          processed: 1,
          created: 0,
          updated: 1
        )
      end
    end

    context 'when processing show with alternative data structure' do
      let(:api_data) do
        [
          {
            'show' => {
              'id' => 2,
              'name' => 'Test Show',
              'network' => { 
                'name' => 'Network',
                'country' => { 'code' => 'UK' }
              }
            },
            'airdate' => '2023-01-01'
          }
        ]
      end

      it 'processes show data correctly' do
        subject
        tv_show = TvShow.first
        expect(tv_show.external_id).to eq(2)
        expect(tv_show.name).to eq('Test Show')
        expect(tv_show.distributor.name).to eq('Network')
        
        release_date = tv_show.release_dates.first
        expect(release_date.country).to eq('UK')
        expect(release_date.release_date).to eq(Date.parse('2023-01-01'))
      end
    end

    context 'when show has no network information' do
      let(:api_data) do
        [
          {
            'id' => 3,
            'name' => 'Test Show'
          }
        ]
      end

      it 'creates show with Unknown distributor' do
        subject
        tv_show = TvShow.first
        expect(tv_show.distributor.name).to eq('Unknown')
      end
    end

    context 'when processing invalid data' do
      let(:api_data) do
        [
          {
            'id' => 4,
            # Missing required name field
            'network' => { 'name' => 'Test Network' }
          }
        ]
      end

      it 'handles errors gracefully' do
        result = subject
        expect(result[:success]).to be false
        expect(result[:stats][:errors]).not_to be_empty
        expect(result[:stats][:processed]).to eq(1)
        expect(result[:stats][:created]).to eq(0)
      end
    end
  end
end