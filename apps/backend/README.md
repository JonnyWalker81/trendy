# Trendy API Backend

A REST API server for the Trendy event tracking application, built with Go, Gin, and Supabase.

## Architecture

This backend follows clean architecture principles with clear separation of concerns:

```
backend/
├── cmd/
│   └── trendy-api/          # CLI application (Cobra)
├── internal/
│   ├── config/              # Configuration management (Viper)
│   ├── handlers/            # HTTP handlers (serialization/deserialization)
│   ├── service/             # Business logic layer
│   ├── repository/          # Data access layer
│   ├── models/              # Domain models
│   └── middleware/          # HTTP middleware
└── pkg/
    └── supabase/            # Supabase client wrapper
```

### Layers

- **Handlers**: HTTP layer, handles request/response serialization
- **Service**: Business logic and validation
- **Repository**: Database access and queries
- **Models**: Domain entities and DTOs

## Requirements

- Go 1.21+
- Supabase account and project

## Setup

1. Copy the environment file:
```bash
cp .env.example .env
```

2. Update the `.env` file with your Supabase credentials:
```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-key-here
```

3. Install dependencies:
```bash
go mod download
```

## Running the Server

### Using the CLI

Build and run:
```bash
go build -o trendy-api ./cmd/trendy-api
./trendy-api serve
```

Run directly:
```bash
go run ./cmd/trendy-api serve
```

With custom port:
```bash
go run ./cmd/trendy-api serve --port 3000
```

### CLI Commands

```bash
# Start the API server
trendy-api serve

# Start with custom port
trendy-api serve --port 3000

# Show help
trendy-api --help
trendy-api serve --help
```

## Configuration

The application can be configured through multiple sources (in order of precedence):

1. Command-line flags
2. Environment variables
3. Configuration file (config.yaml)
4. Default values

### Environment Variables

```bash
# Server
PORT=8080
TRENDY_SERVER_ENV=development  # or production

# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-key-here
```

### Configuration File

Create a `config.yaml` file:

```yaml
server:
  port: "8080"
  env: "development"

supabase:
  url: "https://your-project.supabase.co"
  service_key: "your-service-key-here"
```

## API Endpoints

### Authentication

- `POST /api/v1/auth/signup` - Create a new account
- `POST /api/v1/auth/login` - Login and get access token
- `POST /api/v1/auth/logout` - Logout
- `GET /api/v1/auth/me` - Get current user (requires auth)

### Events

- `GET /api/v1/events` - List events (with pagination)
- `POST /api/v1/events` - Create event
- `GET /api/v1/events/:id` - Get event by ID
- `PUT /api/v1/events/:id` - Update event
- `DELETE /api/v1/events/:id` - Delete event

### Event Types

- `GET /api/v1/event-types` - List event types
- `POST /api/v1/event-types` - Create event type
- `GET /api/v1/event-types/:id` - Get event type by ID
- `PUT /api/v1/event-types/:id` - Update event type
- `DELETE /api/v1/event-types/:id` - Delete event type

### Analytics

- `GET /api/v1/analytics/summary` - Get summary statistics
- `GET /api/v1/analytics/trends` - Get trend data
- `GET /api/v1/analytics/event-type/:id` - Get analytics for specific event type

### Health Check

- `GET /health` - Server health status

## Development

### Project Structure

- `cmd/trendy-api/` - CLI entry point
- `internal/config/` - Configuration management
- `internal/handlers/` - HTTP request handlers
- `internal/service/` - Business logic
- `internal/repository/` - Database operations
- `internal/models/` - Data models
- `internal/middleware/` - HTTP middleware
- `pkg/supabase/` - Supabase client

### Adding New Features

1. **Add models** in `internal/models/models.go`
2. **Create repository interface and implementation** in `internal/repository/`
3. **Implement business logic** in `internal/service/`
4. **Add HTTP handlers** in `internal/handlers/`
5. **Wire up routes** in `cmd/trendy-api/serve.go`

## Testing

```bash
go test ./...
```

## Building

```bash
# Build binary
go build -o trendy-api ./cmd/trendy-api

# Build for production
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o trendy-api ./cmd/trendy-api
```

## Dependencies

- [Gin](https://github.com/gin-gonic/gin) - HTTP web framework
- [Cobra](https://github.com/spf13/cobra) - CLI framework
- [Viper](https://github.com/spf13/viper) - Configuration management
- Supabase - Backend-as-a-Service (PostgreSQL, Auth, Storage)

## License

MIT
