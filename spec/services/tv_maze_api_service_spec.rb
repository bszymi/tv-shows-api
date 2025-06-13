require 'rails_helper'

RSpec.describe TvMazeApiService, type: :service do
  let(:sample_episode_data) do
    [
      {
        'id' => 1,
        'airdate' => '2024-01-01',
        'airstamp' => '2024-01-01T20:00:00+00:00',
        'show' => {
          'id' => 1,
          'name' => 'Test Show 1',
          'type' => 'Scripted',
          'language' => 'English',
          'status' => 'Running',
          'runtime' => 60,
          'premiered' => '2024-01-01',
          'summary' => '<p>Test summary 1</p>',
          'rating' => { 'average' => 8.5 },
          'network' => { 'name' => 'HBO' }
        }
      },
      {
        'id' => 2,
        'airdate' => '2024-01-02',
        'airstamp' => '2024-01-02T21:00:00+00:00',
        'show' => {
          'id' => 2,
          'name' => 'Test Show 2',
          'type' => 'Reality',
          'language' => 'English',
          'status' => 'Ended',
          'runtime' => 30,
          'premiered' => '2023-06-15',
          'summary' => '<p>Test summary 2</p>',
          'rating' => { 'average' => 7.2 },
          'network' => { 'name' => 'CBS' }
        }
      }
    ]
  end

  before do
    # Clean up storage before each test
    TvMazeDataStorage.delete_data
  end

  after do
    # Clean up storage after each test
    TvMazeDataStorage.delete_data
  end

  describe '.fetch_full_schedule' do
    subject { described_class.fetch_full_schedule }

    context 'when no previous data exists (first-time fetch)' do
      before do
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(
            status: 200,
            body: sample_episode_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'processes all data and stores it' do
        result = subject

        expect(result).to include(
          success: true,
          data: sample_episode_data,
          count: 2,
          storage_updated: true
        )
      end

      it 'stores data to file system' do
        subject
        expect(TvMazeDataStorage.data_exists?).to be true
        stored_data = TvMazeDataStorage.read_data
        expect(stored_data).to eq(sample_episode_data)
      end
    end

    context 'when previous data exists and data is unchanged' do
      before do
        # Store initial data
        TvMazeDataStorage.write_data(sample_episode_data)
        
        # Mock API to return same data
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(
            status: 200,
            body: sample_episode_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'detects no changes and skips processing' do
        result = subject

        expect(result).to include(
          success: true,
          data: [],
          count: 0,
          changes: 0,
          skipped: 2
        )
      end
    end

    context 'when previous data exists and data has changed' do
      let(:updated_episode_data) do
        sample_episode_data.dup.tap do |data|
          # Modify first episode
          data[0] = data[0].merge('airstamp' => '2024-01-01T21:00:00+00:00')
          # Add new episode
          data << {
            'id' => 3,
            'airdate' => '2024-01-03',
            'airstamp' => '2024-01-03T20:00:00+00:00',
            'show' => {
              'id' => 3,
              'name' => 'Test Show 3',
              'type' => 'Comedy',
              'language' => 'English',
              'status' => 'Running'
            }
          }
        end
      end

      before do
        # Store initial data
        TvMazeDataStorage.write_data(sample_episode_data)
        
        # Mock API to return updated data
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(
            status: 200,
            body: updated_episode_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'detects changes and returns only changed episodes' do
        result = subject

        expect(result).to include(
          success: true,
          count: 2, # changed episode + new episode
          changes: 2,
          examined: 3,
          storage_updated: true
        )

        # Should contain the modified episode and new episode
        episode_ids = result[:data].map { |ep| ep['id'] }
        expect(episode_ids).to include(1, 3) # changed and new episodes
      end

      it 'updates stored data with new version' do
        subject
        stored_data = TvMazeDataStorage.read_data
        expect(stored_data).to eq(updated_episode_data)
      end
    end

    context 'when force_full_refresh is true' do
      subject { described_class.fetch_full_schedule(force_full_refresh: true) }

      before do
        # Store initial data
        TvMazeDataStorage.write_data(sample_episode_data)
        
        # Mock API to return same data
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(
            status: 200,
            body: sample_episode_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'processes all data regardless of changes' do
        result = subject

        expect(result).to include(
          success: true,
          data: sample_episode_data,
          count: 2,
          storage_updated: true
        )
      end
    end

    context 'when the API request fails' do
      before do
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(status: [500, 'Internal Server Error'])
      end

      it 'returns error response' do
        result = subject
        expect(result).to include(
          success: false,
          data: []
        )
        expect(result[:error]).to match(/HTTP 500/)
      end
    end

    context 'when the API response is invalid JSON' do
      before do
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(status: 200, body: 'invalid json')
      end

      it 'returns JSON parse error' do
        expect(subject).to include(
          success: false,
          error: 'Invalid JSON response',
          data: []
        )
      end
    end

    context 'when a network error occurs' do
      before do
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_raise(StandardError.new('Network error'))
      end

      it 'returns network error' do
        expect(subject).to include(
          success: false,
          error: 'Network error',
          data: []
        )
      end
    end

    context 'when previous data file is corrupted' do
      before do
        # Create corrupted file
        allow(TvMazeDataStorage).to receive(:read_data).and_return(nil)
        allow(TvMazeDataStorage).to receive(:data_exists?).and_return(true)
        
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(
            status: 200,
            body: sample_episode_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'falls back to full processing' do
        result = subject

        expect(result).to include(
          success: true,
          data: sample_episode_data,
          count: 2
        )
      end
    end

    context 'when storage write fails' do
      before do
        allow(TvMazeDataStorage).to receive(:write_data).and_return(false)
        
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(
            status: 200,
            body: sample_episode_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'continues processing but marks storage as failed' do
        result = subject

        expect(result).to include(
          success: true,
          data: sample_episode_data,
          count: 2,
          storage_updated: false
        )
      end
    end
  end

  describe 'TvMazeDataStorage integration' do
    it 'creates storage directory if it does not exist' do
      TvMazeDataStorage.delete_data
      expect(TvMazeDataStorage.write_data(sample_episode_data)).to be true
      expect(TvMazeDataStorage.data_exists?).to be true
    end

    it 'handles empty data gracefully' do
      expect(TvMazeDataStorage.write_data([])).to be true
      expect(TvMazeDataStorage.read_data).to eq([])
    end

    it 'maintains data integrity through read/write cycles' do
      original_data = sample_episode_data
      
      TvMazeDataStorage.write_data(original_data)
      retrieved_data = TvMazeDataStorage.read_data
      
      expect(retrieved_data).to eq(original_data)
    end

    it 'properly cleans up data' do
      TvMazeDataStorage.write_data(sample_episode_data)
      expect(TvMazeDataStorage.data_exists?).to be true
      
      TvMazeDataStorage.delete_data
      expect(TvMazeDataStorage.data_exists?).to be false
    end
  end
end