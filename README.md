# Trendy

<div align="center">
  <img src="apps/ios/trendy/Assets.xcassets/AppIcon.appiconset/trendyAppIcon 1.png" width="120" height="120" alt="Trendy App Icon">

  **A cross-platform event tracking application with analytics**

  [iOS](#ios-app) • [Web](#web-app) • [Backend](#backend-api) • [Setup](#quick-start)
</div>

---

## Overview

Trendy is a comprehensive event tracking platform that helps users log, visualize, and analyze personal events over time. The project is a monorepo containing:

- **iOS App**: Native SwiftUI app with local-first data storage
- **Web App**: React TypeScript progressive web app
- **Backend API**: Go REST API with Supabase integration
- **Shared Types**: Common type definitions across platforms

## Architecture

```
trendy/
├── apps/
│   ├── ios/              # Native iOS app (SwiftUI + SwiftData)
│   ├── web/              # React TypeScript web app (Vite)
│   └── backend/          # Go API server (Gin + Supabase)
├── packages/
│   └── shared-types/     # Shared TypeScript types
├── supabase/             # Database migrations and config
├── flake.nix             # Nix development environment
└── justfile              # Build and automation commands
```

## Quick Start

### Prerequisites

- **For iOS development**: macOS with Xcode 15+
- **For web/backend**: Nix (recommended) or Node.js 20+, Go 1.21+, Yarn

### Using Nix (Recommended)

```bash
# Enter development environment
nix develop

# Or use direnv for automatic activation
direnv allow
```

### Manual Setup

```bash
# Install dependencies
just install

# Set up environment variables
cp apps/backend/.env.example apps/backend/.env
cp apps/web/.env.example apps/web/.env
# Edit .env files with your Supabase credentials

# Build all apps
just build
```

### Running the Apps

```bash
# Run web app (http://localhost:3000)
just dev-web

# Run backend API (http://localhost:8080)
just dev-backend

# Open iOS app in Xcode
just open-ios
```

## Applications

### iOS App

Native iOS application built with SwiftUI and SwiftData for offline-first event tracking.

**Features:**
- Tap bubbles to track events
- Calendar integration
- Analytics and trends
- Local data storage with SwiftData
- iOS 17.0+

**Location:** `apps/ios/`

[View iOS README](apps/ios/README.md)

### Web App

React TypeScript progressive web app with Supabase authentication.

**Features:**
- Dashboard with event overview
- Event management
- Analytics visualization
- Responsive design
- Real-time sync with backend

**Tech Stack:**
- React 18
- TypeScript
- Vite
- React Router
- Supabase Client

**Location:** `apps/web/`

[View Web README](apps/web/README.md)

### Backend API

RESTful API server with clean architecture and Supabase integration.

**Features:**
- User authentication (JWT via Supabase)
- Event and event type CRUD operations
- Analytics endpoints
- Clean architecture (Repository → Service → Handler)

**Tech Stack:**
- Go 1.21+
- Gin web framework
- Cobra (CLI)
- Viper (configuration)
- Supabase (PostgreSQL + Auth)

**Location:** `apps/backend/`

[View Backend README](apps/backend/README.md)

## Development

### Available Commands

```bash
# Show all available commands
just --list

# Installation
just install                # Install all dependencies
just clean                  # Clean build artifacts

# Building
just build                  # Build all apps
just build-web              # Build web app only
just build-backend          # Build backend only
just build-ios              # Build iOS app (macOS only)

# Development
just dev-web                # Run web dev server
just dev-backend            # Run backend dev server

# Testing
just test                   # Run all tests
just test-web               # Run web tests
just test-backend           # Run backend tests

# Linting & Formatting
just lint                   # Lint all code
just fmt                    # Format all code

# Database
just db-setup               # Show Supabase setup instructions
just db-migrate             # Database migration info
```

### Project Structure

```
trendy/
├── apps/
│   ├── backend/
│   │   ├── cmd/trendy-api/      # CLI entry point
│   │   ├── internal/
│   │   │   ├── config/          # Configuration (Viper)
│   │   │   ├── handlers/        # HTTP handlers
│   │   │   ├── service/         # Business logic
│   │   │   ├── repository/      # Data access
│   │   │   ├── models/          # Domain models
│   │   │   └── middleware/      # HTTP middleware
│   │   └── pkg/supabase/        # Supabase client
│   │
│   ├── web/
│   │   └── src/
│   │       ├── components/      # React components
│   │       ├── pages/           # Page components
│   │       ├── lib/             # Utilities and hooks
│   │       └── types/           # TypeScript types
│   │
│   └── ios/
│       └── trendy/
│           ├── Models/          # Data models
│           ├── ViewModels/      # State management
│           ├── Views/           # SwiftUI views
│           └── Utilities/       # Helper classes
│
├── packages/
│   └── shared-types/            # Shared TypeScript types
│
└── supabase/
    ├── migrations.sql           # Database schema
    └── README.md                # Setup instructions
```

## Database Setup

1. Create a Supabase project at [supabase.com](https://supabase.com)
2. Run the migration SQL:
   - Open your Supabase dashboard
   - Go to SQL Editor
   - Copy/paste contents from `supabase/migrations.sql`
   - Execute
3. Configure environment variables with your Supabase credentials

[View Supabase README](supabase/README.md)

## API Endpoints

### Authentication
- `POST /api/v1/auth/signup` - Create account
- `POST /api/v1/auth/login` - Login
- `GET /api/v1/auth/me` - Get current user

### Events
- `GET /api/v1/events` - List events
- `POST /api/v1/events` - Create event
- `GET /api/v1/events/:id` - Get event
- `PUT /api/v1/events/:id` - Update event
- `DELETE /api/v1/events/:id` - Delete event

### Event Types
- `GET /api/v1/event-types` - List event types
- `POST /api/v1/event-types` - Create event type
- `GET /api/v1/event-types/:id` - Get event type
- `PUT /api/v1/event-types/:id` - Update event type
- `DELETE /api/v1/event-types/:id` - Delete event type

### Analytics
- `GET /api/v1/analytics/summary` - Get summary
- `GET /api/v1/analytics/trends` - Get trends
- `GET /api/v1/analytics/event-type/:id` - Event type analytics

## Environment Variables

### Backend (`apps/backend/.env`)
```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-key
PORT=8080
TRENDY_SERVER_ENV=development
```

### Web (`apps/web/.env`)
```bash
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

## Technology Stack

### Frontend
- **iOS**: SwiftUI, SwiftData, EventKit, Swift Charts
- **Web**: React 18, TypeScript, Vite, React Router

### Backend
- **API**: Go, Gin, Cobra, Viper
- **Database**: PostgreSQL (via Supabase)
- **Auth**: Supabase Auth (JWT)

### DevOps
- **Build**: Just, Nix
- **Package Managers**: Yarn (web), Go modules (backend)
- **Development**: Vite (web), Air/fresh (backend, optional)

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Development Environment

This project uses Nix flakes for reproducible development environments:

```bash
# Activate environment
nix develop

# Or with direnv
echo "use flake" > .envrc
direnv allow
```

Includes:
- Node.js 20
- Yarn
- Go 1.22
- Just
- PostgreSQL client tools

## Roadmap

- [x] iOS app with local storage
- [x] Go backend API
- [x] React web app
- [x] Supabase integration
- [x] Clean architecture
- [ ] iOS app sync with backend
- [ ] Real-time updates
- [ ] Advanced analytics
- [ ] Export/import functionality
- [ ] Multi-device sync
- [ ] Mobile web responsiveness
- [ ] Progressive Web App features

## License

MIT

---

<div align="center">
Made with ❤️ using SwiftUI, React, and Go
</div>
