require 'rails_helper'

RSpec.describe TvShowsSyncWorker, type: :worker do
  describe '#perform' do
    let(:sample_data) { [ { 'id' => 1, 'show' => { 'name' => 'Test Show' } } ] }

    before do
      # Clean up any existing storage
      TvMazeDataStorage.delete_data
    end

    after do
      # Clean up after tests
      TvMazeDataStorage.delete_data
    end

    context 'with incremental processing (default)' do
      context 'when API fetch is successful and has new data' do
        let(:api_response) do
          {
            success: true,
            data: sample_data,
            count: 1,
            storage_updated: true
          }
        end

        let(:persistence_response) do
          {
            success: true,
            stats: { processed: 1, created: 1, updated: 0, errors: [] }
          }
        end

        before do
          allow(TvMazeApiService).to receive(:fetch_full_schedule).and_return(api_response)
          allow(TvShowPersistenceService).to receive(:persist_from_api_data).and_return(persistence_response)
        end

        it 'fetches and persists TV shows data successfully' do
          expect(TvMazeApiService).to receive(:fetch_full_schedule).with(force_full_refresh: false)
          expect(TvShowPersistenceService).to receive(:persist_from_api_data).with(api_response[:data])

          subject.perform
        end

        it 'logs success messages' do
          expect(Rails.logger).to receive(:info).with('Starting TV shows sync job (incremental: true)')
          expect(Rails.logger).to receive(:info).with('Processing 1 records (1 changes)')
          expect(Rails.logger).to receive(:info).with('TV shows sync completed successfully: 1 processed, 1 created, 0 updated')

          subject.perform
        end
      end

      context 'when no changes are detected' do
        let(:api_response) do
          {
            success: true,
            data: [],
            count: 0,
            skipped: 5,
            storage_updated: false
          }
        end

        before do
          allow(TvMazeApiService).to receive(:fetch_full_schedule).and_return(api_response)
        end

        it 'skips processing and logs appropriately' do
          expect(Rails.logger).to receive(:info).with('Starting TV shows sync job (incremental: true)')
          expect(Rails.logger).to receive(:info).with('No changes detected - 5 records skipped')
          expect(TvShowPersistenceService).not_to receive(:persist_from_api_data)

          subject.perform
        end
      end

      context 'when data is empty after processing' do
        let(:api_response) do
          {
            success: true,
            data: [],
            count: 0,
            changes: 0,
            examined: 10
          }
        end

        before do
          allow(TvMazeApiService).to receive(:fetch_full_schedule).and_return(api_response)
        end

        it 'skips persistence and logs appropriately' do
          expect(Rails.logger).to receive(:info).with('Starting TV shows sync job (incremental: true)')
          expect(Rails.logger).to receive(:info).with('No new or changed data to process')
          expect(TvShowPersistenceService).not_to receive(:persist_from_api_data)

          subject.perform
        end
      end
    end

    context 'with forced full refresh' do
      let(:api_response) do
        {
          success: true,
          data: sample_data,
          count: 1,
          storage_updated: true
        }
      end

      let(:persistence_response) do
        {
          success: true,
          stats: { processed: 1, created: 1, updated: 0, errors: [] }
        }
      end

      before do
        allow(TvMazeApiService).to receive(:fetch_full_schedule).and_return(api_response)
        allow(TvShowPersistenceService).to receive(:persist_from_api_data).and_return(persistence_response)
      end

      it 'forces full refresh when requested' do
        expect(TvMazeApiService).to receive(:fetch_full_schedule).with(force_full_refresh: true)
        expect(Rails.logger).to receive(:info).with('Starting TV shows sync job (incremental: false)')
        expect(Rails.logger).to receive(:info).with('Processing 1 records (1 changes)')
        expect(Rails.logger).to receive(:info).with('TV shows sync completed successfully: 1 processed, 1 created, 0 updated')

        subject.perform(force_full_refresh: true)
      end
    end

    context 'when API fetch fails' do
      let(:api_response) do
        {
          success: false,
          error: 'API connection failed',
          data: []
        }
      end

      before do
        allow(TvMazeApiService).to receive(:fetch_full_schedule).and_return(api_response)
      end

      it 'logs error and raises exception' do
        expect(Rails.logger).to receive(:info).with('Starting TV shows sync job (incremental: true)')
        expect(Rails.logger).to receive(:error).with('Failed to fetch TV shows data: API connection failed')
        expect(Rails.logger).to receive(:error).with('TV shows sync job failed: API fetch failed: API connection failed')
        expect(Rails.logger).to receive(:error).with(kind_of(String)) # backtrace

        expect { subject.perform }.to raise_error('API fetch failed: API connection failed')
      end
    end

    context 'when persistence has errors' do
      let(:api_response) do
        {
          success: true,
          data: sample_data,
          count: 1,
          storage_updated: true
        }
      end

      let(:persistence_response) do
        {
          success: false,
          stats: {
            processed: 1,
            created: 0,
            updated: 0,
            errors: [ { show_id: 1, error: 'Validation failed' } ]
          }
        }
      end

      before do
        allow(TvMazeApiService).to receive(:fetch_full_schedule).and_return(api_response)
        allow(TvShowPersistenceService).to receive(:persist_from_api_data).and_return(persistence_response)
      end

      it 'logs errors but does not raise exception' do
        expect(Rails.logger).to receive(:info).with('Starting TV shows sync job (incremental: true)')
        expect(Rails.logger).to receive(:info).with('Processing 1 records (1 changes)')
        expect(Rails.logger).to receive(:error).with('TV shows sync completed with errors: 1 errors out of 1 processed')
        expect(Rails.logger).to receive(:error).with('Show ID 1: Validation failed')

        expect { subject.perform }.not_to raise_error
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(TvMazeApiService).to receive(:fetch_full_schedule).and_raise(StandardError.new('Unexpected error'))
      end

      it 'logs error and re-raises exception' do
        expect(Rails.logger).to receive(:info).with('Starting TV shows sync job (incremental: true)')
        expect(Rails.logger).to receive(:error).with('TV shows sync job failed: Unexpected error')
        expect(Rails.logger).to receive(:error).with(kind_of(String)) # backtrace

        expect { subject.perform }.to raise_error('Unexpected error')
      end
    end
  end
end
