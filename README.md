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
