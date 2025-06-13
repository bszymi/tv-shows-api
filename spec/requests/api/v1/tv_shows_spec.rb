require 'rails_helper'

RSpec.describe 'Api::V1::TvShows', type: :request do
  # Authentication headers for tests
  let(:auth_header) { "Basic #{Base64.encode64('api_user:secure_password').strip}" }
  let(:headers) { { 'Authorization' => auth_header } }
  describe 'GET /api/v1/tv_shows' do
    let!(:distributor1) { Distributor.create!(name: 'CBS') }
    let!(:distributor2) { Distributor.create!(name: 'NBC') }

    let!(:show1) do
      TvShow.create!(
        external_id: 1,
        name: 'Show A',
        show_type: 'Scripted',
        language: 'English',
        status: 'Running',
        runtime: 60,
        premiered: Date.parse('2020-01-01'),
        summary: 'Test summary 1',
        rating: 8.5,
        distributor: distributor1
      )
    end

    let!(:show2) do
      TvShow.create!(
        external_id: 2,
        name: 'Show B',
        show_type: 'Reality',
        language: 'English',
        status: 'Ended',
        runtime: 30,
        premiered: Date.parse('2019-06-15'),
        summary: 'Test summary 2',
        rating: 7.2,
        distributor: distributor2
      )
    end

    let!(:release_date1) { ReleaseDate.create!(tv_show: show1, country: 'US', release_date: Date.parse('2020-01-01')) }
    let!(:release_date2) { ReleaseDate.create!(tv_show: show2, country: 'UK', release_date: Date.parse('2019-06-15')) }

    context 'without filters' do
      it 'returns all TV shows with pagination' do
        get '/api/v1/tv_shows', headers: headers

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['tv_shows']).to be_an(Array)
        expect(json_response['tv_shows'].size).to eq(2)

        # Check deterministic ordering (by name, then id)
        expect(json_response['tv_shows'][0]['name']).to eq('Show A')
        expect(json_response['tv_shows'][1]['name']).to eq('Show B')

        # Check pagination metadata
        expect(json_response['meta']).to include(
          'current_page' => 1,
          'total_pages' => 1,
          'total_count' => 2,
          'per_page' => 25
        )
      end

      it 'includes associated data' do
        get '/api/v1/tv_shows', headers: headers

        json_response = JSON.parse(response.body)
        first_show = json_response['tv_shows'][0]

        expect(first_show).to include(
          'id' => show1.id,
          'external_id' => 1,
          'name' => 'Show A',
          'show_type' => 'Scripted',
          'language' => 'English',
          'status' => 'Running',
          'runtime' => 60,
          'premiered' => '2020-01-01',
          'summary' => 'Test summary 1',
          'rating' => '8.5'
        )

        expect(first_show['distributor']).to include(
          'id' => distributor1.id,
          'name' => 'CBS'
        )

        expect(first_show['release_dates']).to be_an(Array)
        expect(first_show['release_dates'][0]).to include(
          'country' => 'US',
          'release_date' => '2020-01-01'
        )
      end
    end

    context 'with distributor filter' do
      it 'returns shows for specified distributor' do
        get '/api/v1/tv_shows', headers: headers, params: { distributor: 'CBS' }

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['tv_shows'].size).to eq(1)
        expect(json_response['tv_shows'][0]['name']).to eq('Show A')
        expect(json_response['tv_shows'][0]['distributor']['name']).to eq('CBS')
      end
    end

    context 'with country filter' do
      it 'returns shows for specified country' do
        get '/api/v1/tv_shows', headers: headers, params: { country: 'UK' }

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['tv_shows'].size).to eq(1)
        expect(json_response['tv_shows'][0]['name']).to eq('Show B')
      end
    end

    context 'with rating filter' do
      it 'returns shows with rating above minimum' do
        get '/api/v1/tv_shows', headers: headers, params: { min_rating: 8.0 }

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['tv_shows'].size).to eq(1)
        expect(json_response['tv_shows'][0]['name']).to eq('Show A')
        expect(json_response['tv_shows'][0]['rating']).to eq('8.5')
      end
    end

    context 'with pagination' do
      before do
        # Create additional shows to test pagination
        15.times do |i|
          TvShow.create!(
            external_id: 100 + i,
            name: "Show #{i + 3}",
            distributor: distributor1
          )
        end
      end

      it 'respects per_page parameter' do
        get '/api/v1/tv_shows', headers: headers, params: { per_page: 5 }

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['tv_shows'].size).to eq(5)
        expect(json_response['meta']).to include(
          'current_page' => 1,
          'total_pages' => 4,
          'total_count' => 17,
          'per_page' => 5
        )
      end

      it 'respects page parameter' do
        get '/api/v1/tv_shows', headers: headers, params: { per_page: 5, page: 2 }

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['tv_shows'].size).to eq(5)
        expect(json_response['meta']).to include(
          'current_page' => 2,
          'total_pages' => 4,
          'total_count' => 17,
          'per_page' => 5
        )
      end
    end

    context 'with multiple filters' do
      let!(:show3) do
        TvShow.create!(
          external_id: 3,
          name: 'Show C',
          rating: 9.0,
          distributor: distributor1
        )
      end

      let!(:release_date3) { ReleaseDate.create!(tv_show: show3, country: 'US', release_date: Date.parse('2021-01-01')) }

      it 'applies all filters correctly' do
        get '/api/v1/tv_shows', headers: headers, params: { distributor: 'CBS', country: 'US', min_rating: 8.0 }

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['tv_shows'].size).to eq(2)

        show_names = json_response['tv_shows'].map { |show| show['name'] }
        expect(show_names).to contain_exactly('Show A', 'Show C')
      end
    end
  end
end
