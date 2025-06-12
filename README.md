# TV Shows API

Rails API application for managing TV show data fetched from TVMaze API.

## Requirements

- Ruby 3.4.2
- Rails 8.0.2
- PostgreSQL
- Redis (for Sidekiq)

## Setup Instructions

### Local Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/tv-shows-api.git
cd tv-shows-api
```

2. Install dependencies:
```bash
bundle install
```

3. Setup database:
```bash
rails db:create
rails db:migrate
```

4. Run the server:
```bash
rails server
```

### Docker Setup

1. Build and start services:
```bash
docker-compose up --build
```

2. In another terminal, create and migrate the database:
```bash
docker-compose exec web rails db:create
docker-compose exec web rails db:migrate
```

3. Access the application at http://localhost:3000
   - Sidekiq web interface: http://localhost:3000/sidekiq

4. Stop services:
```bash
docker-compose down
```

## Database Schema

### Tables

1. **distributors**
   - `id` (primary key)
   - `name` (string, unique)
   - `created_at`, `updated_at`

2. **tv_shows**
   - `id` (primary key)
   - `external_id` (integer, unique) - TVMaze show ID
   - `name` (string)
   - `show_type` (string) - e.g., "Scripted", "Animation"
   - `language` (string)
   - `status` (string) - e.g., "Running", "Ended"
   - `runtime` (integer) - in minutes
   - `premiered` (date)
   - `summary` (text)
   - `official_site` (string)
   - `image_url` (string)
   - `rating` (decimal, precision: 3, scale: 1)
   - `distributor_id` (foreign key)
   - `created_at`, `updated_at`

3. **release_dates**
   - `id` (primary key)
   - `tv_show_id` (foreign key)
   - `country` (string)
   - `release_date` (date)
   - `created_at`, `updated_at`
   - Unique constraint on [tv_show_id, country]

### Indices
- distributors: name (unique)
- tv_shows: external_id (unique), distributor_id
- release_dates: country, release_date, [tv_show_id, country] (unique)

## Models and Associations

### Distributor
- `has_many :tv_shows, dependent: :destroy`
- Validates name presence and uniqueness

### TvShow
- `belongs_to :distributor`
- `has_many :release_dates, dependent: :destroy`
- Validates external_id presence and uniqueness
- Validates name presence
- Validates rating between 0-10 (optional)
- Validates runtime > 0 (optional)
- Scopes: `by_distributor`, `by_country`, `by_rating`

### ReleaseDate
- `belongs_to :tv_show`
- Validates country and release_date presence
- Validates country uniqueness per tv_show

## Services

### TvMazeApiService
- Fetches TV show data from TVMaze API (https://api.tvmaze.com/schedule/full)
- Handles HTTP errors and timeouts gracefully
- Returns structured response with success/error status
- Includes comprehensive error logging

### TvShowPersistenceService
- Processes and persists TV show data from API responses
- Implements idempotent operations using `find_or_initialize_by` and `find_or_create_by`
- Handles multiple data formats from TVMaze API
- Creates distributors, TV shows, and release dates in a single transaction
- Provides detailed statistics on processing results (created, updated, errors)
- Graceful error handling with detailed error reporting

## Background Jobs

### Sidekiq Configuration
- Uses Redis for job queue storage
- Configured with 3 retries for failed jobs
- Web interface available at `/sidekiq` for monitoring

### TvShowsSyncWorker
- Scheduled to run daily at 2 AM UTC using sidekiq-cron
- Fetches latest TV show data from TVMaze API
- Persists data using the TvShowPersistenceService
- Comprehensive logging of sync progress and errors
- Graceful error handling with job retries

## API Documentation

API endpoints and usage will be documented as they are implemented.
