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

Instructions will be added in the next commit.

## API Documentation

API endpoints and usage will be documented as they are implemented.
