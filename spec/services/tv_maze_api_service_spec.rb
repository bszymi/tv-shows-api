require 'rails_helper'

RSpec.describe TvMazeApiService, type: :service do
  describe '.fetch_full_schedule' do
    subject { described_class.fetch_full_schedule }

    context 'when the API request is successful' do
      let(:sample_response) do
        [
          {
            'id' => 1,
            'name' => 'Under the Dome',
            'type' => 'Scripted',
            'language' => 'English',
            'status' => 'Ended',
            'runtime' => 60,
            'premiered' => '2013-06-24',
            'summary' => '<p>Test summary</p>',
            'officialSite' => 'http://www.cbs.com/shows/under-the-dome/',
            'image' => { 'medium' => 'http://static.tvmaze.com/uploads/images/medium_portrait/0/1.jpg' },
            'rating' => { 'average' => 6.5 },
            'network' => { 'name' => 'CBS' }
          }
        ]
      end

      before do
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(
            status: 200,
            body: sample_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns successful response with data' do
        expect(subject).to include(
          success: true,
          data: sample_response,
          count: 1
        )
      end
    end

    context 'when the API request fails' do
      before do
        stub_request(:get, 'https://api.tvmaze.com/schedule/full')
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns error response' do
        result = subject
        expect(result[:data]).to eq([])
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
          error: 'Network error',
          data: []
        )
      end
    end
  end
end