# Trendy Web App

A React TypeScript web application for tracking events and visualizing patterns, built with Vite and Supabase.

## Tech Stack

- **React 18** - UI library
- **TypeScript** - Type safety
- **Vite** - Build tool and dev server
- **React Router** - Client-side routing
- **Supabase** - Backend and authentication
- **Tailwind CSS** (styles inline for now) - Styling

## Features

- User authentication (login/signup)
- Dashboard with event overview
- Event list management
- Analytics and trends
- Settings and event type management

## Setup

1. Install dependencies:
```bash
yarn install
```

2. Copy environment file:
```bash
cp .env.example .env
```

3. Update `.env` with your Supabase credentials:
```
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key-here
```

## Development

Start the development server:
```bash
yarn dev
```

The app will be available at `http://localhost:3000`

## Build

Build for production:
```bash
yarn build
```

Preview production build:
```bash
yarn preview
```

## Project Structure

```
src/
├── components/      # Reusable UI components
├── pages/           # Page components (routed views)
├── lib/             # Utilities and hooks
│   ├── supabase.ts  # Supabase client
│   └── useAuth.tsx  # Auth hook
├── types/           # TypeScript type definitions
├── App.tsx          # Main app component with routing
├── main.tsx         # Entry point
└── index.css        # Global styles
```

## API Integration

The app communicates with the Go backend API running on `http://localhost:8080`. The Vite proxy configuration forwards `/api` requests to the backend.

## Environment Variables

- `VITE_SUPABASE_URL` - Your Supabase project URL
- `VITE_SUPABASE_ANON_KEY` - Your Supabase anon/public key

## Available Scripts

- `yarn dev` - Start development server
- `yarn build` - Build for production
- `yarn preview` - Preview production build
- `yarn lint` - Run ESLint

## License

MIT
