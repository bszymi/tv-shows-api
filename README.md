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

#### Accessing Sidekiq Web UI

The Sidekiq Web UI is accessible in development mode for monitoring background jobs:

**Development/Test Access:**
```bash
# Start the Rails server
rails server

# Access Sidekiq Web UI
open http://localhost:3000/sidekiq
```

**Features Available:**
- Real-time job monitoring (queued, processing, failed)
- Job retry functionality
- Queue statistics and metrics
- Scheduled job management (sidekiq-cron)
- Redis connection information

**Important Notes:**
- Session middleware is only enabled in development and test environments
- In production, implement proper authentication before enabling the Web UI
- The API remains fully functional without sessions - they're only needed for the Web UI

**Production Security:**
For production environments, secure the Sidekiq Web UI with authentication:

```ruby
# config/routes.rb (production example)
require 'sidekiq/web'

# Use HTTP Basic Auth or integrate with your authentication system
Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(
    ::Digest::SHA256.hexdigest(username),
    ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_USERNAME"])
  ) && ActiveSupport::SecurityUtils.secure_compare(
    ::Digest::SHA256.hexdigest(password),
    ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_PASSWORD"])
  )
end

mount Sidekiq::Web => '/sidekiq'
```

### TvShowsSyncWorker
- Scheduled to run daily at 2 AM UTC using sidekiq-cron
- Fetches latest TV show data from TVMaze API
- Persists data using the TvShowPersistenceService
- Comprehensive logging of sync progress and errors
- Graceful error handling with job retries

## Database Optimization

### Performance Indices
- **rating**: Partial index for non-null ratings to optimize rating-based filters
- **status**: Index on show status for filtering by running/ended shows
- **language**: Index for language-based filtering
- **premiered**: Index for date-range queries and sorting
- **name**: Index for name-based searches and sorting
- **composite indices**: 
  - `[status, rating]` for combined status and rating queries
  - `[distributor_id, rating]` for distributor-specific rating queries
  - `[country, release_date]` for country-specific release queries

### Analytical Query Examples

The application includes complex analytical queries demonstrating PostgreSQL capabilities:

#### 1. Distributor Performance Analysis
```sql
SELECT 
  d.name as distributor_name,
  COUNT(t.id) as total_shows,
  AVG(t.rating) as avg_rating,
  MIN(t.rating) as min_rating,
  MAX(t.rating) as max_rating
FROM distributors d
JOIN tv_shows t ON d.id = t.distributor_id
WHERE t.rating IS NOT NULL
GROUP BY d.id, d.name
HAVING COUNT(t.id) >= 3
ORDER BY avg_rating DESC;
```

#### 2. Time Series Analysis with Window Functions
```sql
WITH decade_stats AS (
  SELECT 
    EXTRACT(DECADE FROM premiered) * 10 as decade,
    COUNT(*) as show_count
  FROM tv_shows 
  WHERE premiered IS NOT NULL
  GROUP BY EXTRACT(DECADE FROM premiered)
)
SELECT 
  decade,
  show_count,
  SUM(show_count) OVER (ORDER BY decade ROWS UNBOUNDED PRECEDING) as running_total,
  ROUND(100.0 * show_count / SUM(show_count) OVER (), 2) as percentage
FROM decade_stats
ORDER BY decade;
```

#### 3. CTEs and Advanced Aggregations
```sql
WITH country_rankings AS (
  SELECT 
    rd.country,
    COUNT(DISTINCT rd.tv_show_id) as unique_shows,
    AVG(ts.rating) FILTER (WHERE ts.rating IS NOT NULL) as avg_rating
  FROM release_dates rd
  JOIN tv_shows ts ON rd.tv_show_id = ts.id
  GROUP BY rd.country
)
SELECT 
  country,
  unique_shows,
  PERCENT_RANK() OVER (ORDER BY unique_shows) as percentile_rank
FROM country_rankings
WHERE unique_shows >= 5
ORDER BY unique_shows DESC;
```

### Running Analytics
```bash
# Generate sample data for testing
rails analytics:generate_sample_data

# Run analytical query examples
rails analytics:run_examples
```

## Incremental Data Processing

The TV Shows API includes intelligent incremental data processing to minimize unnecessary database operations and API calls.

### How It Works

The system automatically:

1. **First Run**: Downloads all data from TVMaze API and stores it locally (or in S3 for production)
2. **Subsequent Runs**: Downloads new data, compares it with the stored version using SHA256 hashing
3. **Change Detection**: Identifies only new or modified episodes using efficient diff algorithms
4. **Selective Processing**: Processes only changed records, reducing database load
5. **Storage Update**: Replaces the stored data with the new version after successful processing

### Storage Configuration

#### Local Development
- **Path**: `storage/tvmaze_data.json`
- **Format**: Pretty-printed JSON for easy debugging
- **Automatic**: Directory creation and cleanup

#### Production (S3)
- **Bucket**: Set via `TV_MAZE_S3_BUCKET` environment variable (default: `tv-shows-api-data`)
- **Key**: Set via `TV_MAZE_S3_KEY` environment variable (default: `tvmaze_data.json`)
- **Fallback**: Automatically falls back to local storage if S3 is unavailable
- **Credentials**: Uses IAM instance profiles in production, AWS credentials in development

### Environment Variables

```bash
# Optional S3 configuration (production only)
TV_MAZE_S3_BUCKET=your-bucket-name
TV_MAZE_S3_KEY=tvmaze_data.json
AWS_REGION=us-east-1

# Development only (S3 fallback)
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
```

### Manual Operations

```bash
# Run incremental sync (default behavior)
TvShowsSyncWorker.perform_async

# Force full refresh (ignores cached data)
TvShowsSyncWorker.perform_async(force_full_refresh: true)

# Check what data is currently cached
TvMazeDataStorage.data_exists?
TvMazeDataStorage.read_data&.size

# Clear cached data
TvMazeDataStorage.delete_data
```

### API Usage

```ruby
# Incremental processing (default)
result = TvMazeApiService.fetch_full_schedule
# Returns: { success: true, data: [...], count: N, changes: M, examined: Total }

# Force full refresh
result = TvMazeApiService.fetch_full_schedule(force_full_refresh: true)
# Returns: { success: true, data: [...], count: N, storage_updated: true }

# No changes detected
# Returns: { success: true, data: [], count: 0, changes: 0, skipped: N }
```

### Performance Benefits

- **Reduced API Load**: Only processes changed data
- **Faster Sync Times**: Skips unchanged records entirely
- **Lower Database Load**: Fewer INSERT/UPDATE operations
- **Efficient Storage**: Compressed JSON with hash-based change detection
- **Reliable Fallbacks**: Graceful handling of corrupted or missing cache files

### Monitoring

The system provides detailed logging for monitoring incremental processing:

```
[INFO] Starting TVMaze data fetch (force_full_refresh: false)
[INFO] Checking for incremental changes
[INFO] Data changes detected, finding differences
[INFO] Found 15 changed episodes out of 1000 total
[INFO] Updated storage with 1000 records (15 changes)
[INFO] Processing 15 records (15 changes)
[INFO] TV shows sync completed successfully: 15 processed, 5 created, 10 updated
[INFO] Incremental processing: 15 changes out of 1000 examined
```

## Deployment

### AWS Deployment

For production deployment on AWS, see the comprehensive [AWS Deployment Guide](docs/aws-deployment.md) which covers:

#### Recommended Architecture
- **Compute**: ECS with Fargate for serverless containers
- **Database**: RDS PostgreSQL with Multi-AZ deployment
- **Cache/Queue**: ElastiCache Redis for Sidekiq
- **Load Balancer**: Application Load Balancer with health checks
- **Monitoring**: CloudWatch + custom metrics
- **Security**: VPC, Security Groups, Secrets Manager

#### Key Features
- Auto-scaling based on CPU/memory utilization
- High availability with multi-AZ deployment
- Zero-downtime deployments with blue/green strategy
- Comprehensive monitoring and alerting
- Cost optimization for different environments
- Disaster recovery and backup strategies

#### Quick Start
```bash
# Build and push to ECR
docker build -t tv-shows-api .
docker tag tv-shows-api:latest ACCOUNT.dkr.ecr.REGION.amazonaws.com/tv-shows-api:latest
docker push ACCOUNT.dkr.ecr.REGION.amazonaws.com/tv-shows-api:latest

# Deploy with ECS
aws ecs update-service --cluster tv-shows-api --service tv-shows-api-web --force-new-deployment
```

#### Estimated Costs
- **Development**: ~$50-80/month
- **Production**: ~$300-500/month

See the [full deployment guide](docs/aws-deployment.md) for detailed setup instructions, infrastructure templates, and best practices.

## CI/CD Pipeline

### GitHub Actions Workflow

The project includes a comprehensive CI/CD pipeline using GitHub Actions:

#### Pipeline Stages

1. **Test Stage**
   - Runs RSpec tests with PostgreSQL and Redis services
   - Generates test reports in JUnit XML format
   - Covers all application functionality including background jobs

2. **Lint Stage**
   - Runs RuboCop for code style consistency
   - Enforces Rails best practices and conventions

3. **Security Stage**
   - Runs Brakeman security scanner
   - Generates security vulnerability reports

4. **Build Stage**
   - Builds multi-platform Docker images (AMD64/ARM64)
   - Pushes to GitHub Container Registry
   - Uses Docker layer caching for faster builds

5. **Deploy Stages**
   - **Staging**: Auto-deploys on main branch pushes
   - **Production**: Deploys on GitHub releases
   - Includes environment protection rules

6. **SBOM Generation**
   - Generates Software Bill of Materials for releases
   - Enables supply chain security tracking

#### Key Features

- **Parallel execution** of test, lint, and security jobs
- **Multi-platform** Docker builds (AMD64/ARM64)
- **Artifact management** for test results and security reports
- **Environment protection** with approval workflows
- **Automated deployments** with rollback capabilities
- **Container scanning** and vulnerability assessment

#### Usage

```bash
# Trigger CI on pull request
git checkout -b feature/new-feature
git push origin feature/new-feature

# Deploy to staging (automatic on main branch)
git checkout main
git merge feature/new-feature
git push origin main

# Deploy to production (create release)
git tag v1.0.0
git push origin v1.0.0
# Create GitHub release from tag
```

### Deployment Script

A comprehensive deployment script is provided at `scripts/deploy.sh`:

```bash
# Deploy to staging
./scripts/deploy.sh deploy staging v1.0.0

# Deploy to production  
./scripts/deploy.sh deploy production v1.0.0

# Rollback to previous version
./scripts/deploy.sh rollback 123
```

The script handles:
- Docker image building and ECR pushing
- Database migrations as one-time ECS tasks
- ECS service updates with health checks
- Rollback to previous task definition revisions

## Authentication

### Basic HTTP Authentication

The API uses HTTP Basic Authentication to secure access to endpoints.

#### Configuration

Authentication credentials can be configured via:

1. **Environment Variables** (recommended for production):
   ```bash
   export API_USERNAME=your_username
   export API_PASSWORD=your_secure_password
   ```

2. **Rails Credentials** (encrypted):
   ```bash
   rails credentials:edit
   ```
   ```yaml
   api_username: your_username
   api_password: your_secure_password
   ```

3. **Default Values** (development only):
   - Username: `api_user`
   - Password: `secure_password`

#### Usage

Include HTTP Basic Authentication header in all API requests:

```bash
# Using curl
curl -u api_user:secure_password http://localhost:3000/api/v1/tv_shows

# Using Authorization header
curl -H "Authorization: Basic YXBpX3VzZXI6c2VjdXJlX3Bhc3N3b3Jk" http://localhost:3000/api/v1/tv_shows

# Using HTTPie
http -a api_user:secure_password localhost:3000/api/v1/tv_shows
```

#### Development Mode

In development, authentication can be bypassed by adding `?skip_auth=true` parameter:

```bash
curl http://localhost:3000/api/v1/tv_shows?skip_auth=true
```

#### Security Features

- **Secure string comparison**: Prevents timing attacks using `ActiveSupport::SecurityUtils.secure_compare`
- **Proper HTTP status codes**: Returns 401 Unauthorized with WWW-Authenticate header
- **Environment-based configuration**: Supports different credentials per environment
- **Base64 encoding**: Standard HTTP Basic Authentication format

## API Documentation

### GET /api/v1/tv_shows

Retrieve TV shows with filtering and pagination.

**Authentication Required**: HTTP Basic Authentication

#### Query Parameters

- `page` (integer, optional): Page number for pagination (default: 1)
- `per_page` (integer, optional): Number of items per page (default: 25, max: 100)
- `distributor` (string, optional): Filter by distributor name (e.g., "CBS", "NBC")
- `country` (string, optional): Filter by release country code (e.g., "US", "UK")
- `min_rating` (decimal, optional): Filter shows with rating >= this value

#### Response Format

```json
{
  "tv_shows": [
    {
      "id": 1,
      "external_id": 123,
      "name": "Show Name",
      "show_type": "Scripted",
      "language": "English",
      "status": "Running",
      "runtime": 60,
      "premiered": "2020-01-01",
      "summary": "Show description",
      "official_site": "https://example.com",
      "image_url": "https://example.com/image.jpg",
      "rating": "8.5",
      "distributor": {
        "id": 1,
        "name": "CBS"
      },
      "release_dates": [
        {
          "id": 1,
          "country": "US",
          "release_date": "2020-01-01"
        }
      ]
    }
  ],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 125,
    "per_page": 25
  }
}
```

#### Examples

- Get all shows: `curl -u api_user:secure_password /api/v1/tv_shows`
- Filter by distributor: `curl -u api_user:secure_password /api/v1/tv_shows?distributor=CBS`
- Filter by country: `curl -u api_user:secure_password /api/v1/tv_shows?country=US`
- Filter by rating: `curl -u api_user:secure_password /api/v1/tv_shows?min_rating=8.0`
- Combined filters: `curl -u api_user:secure_password /api/v1/tv_shows?distributor=CBS&country=US&min_rating=7.5`
- Pagination: `curl -u api_user:secure_password /api/v1/tv_shows?page=2&per_page=10`

## Testing

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test files
bundle exec rspec spec/models/
bundle exec rspec spec/services/
bundle exec rspec spec/requests/

# Run with coverage (if simplecov is added)
COVERAGE=true bundle exec rspec

# Run tests in parallel (for large test suites)
bundle exec parallel_rspec spec/
```

### Test Coverage

The application includes comprehensive tests covering:

- **Model validations and associations** (17 examples)
- **Service classes** with mocked external dependencies (32 examples)
- **API endpoints** with authentication and error handling (15 examples)
- **Background jobs** and worker functionality (5 examples)
- **Database analytical queries** (3 examples)

**Total: 55 test examples, 0 failures**

### Test Types

1. **Unit Tests**: Models, services, and utilities
2. **Integration Tests**: API endpoints with full request/response cycle
3. **Service Tests**: External API integration with mocked responses
4. **Worker Tests**: Background job processing and error handling

## Performance Considerations

### Database Performance

- **Optimized indices**: 12 strategic indices for common query patterns
- **Connection pooling**: Configured for concurrent requests
- **Query optimization**: Uses `includes()` to prevent N+1 queries
- **Pagination**: Kaminari gem with configurable page sizes

### Application Performance

- **Background processing**: Sidekiq for non-blocking operations
- **Caching strategy**: Redis for session storage and job queues
- **Database optimization**: Partial indices and composite keys
- **API serialization**: ActiveModelSerializers for consistent JSON output

### Scaling Considerations

- **Horizontal scaling**: Stateless application design
- **Database scaling**: Read replicas and connection pooling
- **Queue scaling**: Multiple Sidekiq workers and queue priorities
- **Cache scaling**: Redis clustering for high availability

## Monitoring and Observability

### Logging

- **Structured logging**: JSON format for production environments
- **Log levels**: Configurable per environment
- **Request logging**: All API requests with response times
- **Background job logging**: Job execution and failure tracking

### Metrics

- **Application metrics**: Custom CloudWatch metrics
- **Database metrics**: Query performance and connection stats
- **Queue metrics**: Job processing rates and queue depths
- **System metrics**: CPU, memory, and disk utilization

### Health Checks

- **Application health**: `/up` endpoint for load balancer checks
- **Database connectivity**: Verified in health checks
- **Redis connectivity**: Queue system health verification
- **External API health**: TVMaze API connection status

## Security

### Data Protection

- **Secrets management**: Environment variables and Rails credentials
- **SQL injection prevention**: Parameterized queries and ActiveRecord
- **XSS prevention**: JSON API with proper content types
- **Timing attack prevention**: Secure string comparisons

### Network Security

- **Authentication**: HTTP Basic Authentication for all API endpoints
- **HTTPS enforcement**: SSL/TLS in production environments
- **CORS configuration**: Controlled cross-origin access
- **Rate limiting**: Configurable request throttling (can be added)

### Infrastructure Security

- **VPC isolation**: Private subnets for database and cache
- **Security groups**: Minimal required port access
- **IAM roles**: Principle of least privilege
- **Encryption**: At-rest and in-transit data encryption

## Troubleshooting

### Common Issues

1. **Database connection errors**
   ```bash
   # Check database configuration
   rails db:migrate:status
   
   # Test connection
   rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1')"
   ```

2. **Redis connection issues**
   ```bash
   # Test Redis connection
   rails runner "puts Sidekiq.redis(&:ping)"
   
   # Check Sidekiq status
   bundle exec sidekiq
   ```

3. **API authentication failures**
   ```bash
   # Test with curl
   curl -u api_user:secure_password http://localhost:3000/api/v1/tv_shows
   
   # Check environment variables
   echo $API_USERNAME $API_PASSWORD
   ```

### Debug Mode

Enable debug logging in development:

```ruby
# config/environments/development.rb
config.log_level = :debug
```

### Performance Debugging

```bash
# Database query analysis
rails runner "puts TvShow.by_rating(8.0).to_sql"

# Explain query plans
rails runner "puts TvShow.joins(:distributor).explain"

# Memory profiling (add memory_profiler gem)
bundle exec ruby -r memory_profiler script/profile_memory.rb
```

## Contributing

### Development Workflow

1. **Fork and clone** the repository
2. **Create feature branch** from main
3. **Write tests** for new functionality
4. **Implement changes** following existing patterns
5. **Run test suite** and ensure all tests pass
6. **Submit pull request** with clear description

### Code Standards

- **RuboCop compliance**: Follow Rails omakase style guide
- **Test coverage**: Maintain high test coverage for new code
- **Documentation**: Update README for significant changes
- **Security**: Run Brakeman security scanner before commits

### Pull Request Process

1. All CI checks must pass (tests, linting, security)
2. Code review by at least one maintainer
3. Documentation updates included
4. No merge conflicts with main branch

## Trade-offs and Design Decisions

### Architecture Decisions

1. **Rails API-only mode**: Optimized for API performance, excludes unused middleware
2. **PostgreSQL choice**: ACID compliance, JSON support, and advanced query capabilities
3. **Sidekiq for background jobs**: Reliable, Redis-based job processing with good monitoring
4. **Basic HTTP authentication**: Simple, standards-compliant, suitable for service-to-service communication

### Data Model Trade-offs

1. **Separate release_dates table**: Normalized design allows multiple release dates per show
2. **Denormalized distributor data**: Trades storage for query performance
3. **External ID storage**: Maintains reference to TVMaze API for future reconciliation
4. **Rating as decimal**: Preserves precision for analytical queries

### Performance Trade-offs

1. **Eager loading associations**: Prevents N+1 queries at cost of memory usage
2. **Database indices**: Improved query performance with increased storage overhead
3. **Pagination default**: Balances response time with data completeness
4. **Background processing**: Better user experience with eventual consistency

### Security Trade-offs

1. **Basic auth over JWT**: Simpler implementation, suitable for server-to-server
2. **Environment-based secrets**: Balance between security and deployment simplicity
3. **Development auth bypass**: Convenience vs. production-like testing

## License

This project is licensed under the MIT License - see the LICENSE file for details.
