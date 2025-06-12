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

4. Stop services:
```bash
docker-compose down
```

## API Documentation

API endpoints and usage will be documented as they are implemented.
