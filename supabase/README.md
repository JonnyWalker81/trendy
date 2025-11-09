# Supabase Configuration

This directory contains database migrations and configuration for the Trendy application.

## Setup

1. **Create a Supabase Project**
   - Go to [https://supabase.com](https://supabase.com)
   - Create a new project
   - Note your project URL and keys

2. **Run Migrations**
   - Open your Supabase project dashboard
   - Go to the SQL Editor
   - Copy and paste the contents of `migrations.sql`
   - Click "Run" to execute the migrations

3. **Configure Environment Variables**

   **Backend** (`apps/backend/.env`):
   ```bash
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_SERVICE_KEY=your-service-role-key
   PORT=8080
   ```

   **Web** (`apps/web/.env`):
   ```bash
   VITE_SUPABASE_URL=https://your-project.supabase.co
   VITE_SUPABASE_ANON_KEY=your-anon-public-key
   ```

## Database Schema

### Tables

#### `users`
- Extends Supabase auth.users
- Stores additional user information
- Automatically created via trigger on signup

#### `event_types`
- User-defined categories for events
- Fields: name, color, icon
- Unique per user

#### `events`
- Individual event records
- Links to event_types and users
- Includes timestamp and optional notes

### Security

All tables have Row Level Security (RLS) enabled:
- Users can only access their own data
- Policies enforce user isolation
- Service role key bypasses RLS for backend operations

### Indexes

Optimized indexes for:
- User-based queries
- Time-based sorting
- Event type lookups

## Key Features

- **Automatic User Creation**: Trigger creates user record on signup
- **Updated Timestamps**: Auto-update `updated_at` on record changes
- **Foreign Key Constraints**: Maintain referential integrity
- **Cascading Deletes**: Clean up related records

## Testing

After running migrations, test with:

```sql
-- Check tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public';

-- Check RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public';
```

## Backup

Supabase automatically backs up your database. You can also:
- Export data via Supabase dashboard
- Use `pg_dump` for manual backups
- Set up automated backup jobs

## Troubleshooting

### Common Issues

1. **Trigger not firing**: Ensure the auth schema exists and is accessible
2. **RLS blocking queries**: Check policies match your use case
3. **Missing UUID extension**: Run `CREATE EXTENSION "uuid-ossp";`

### Support

- [Supabase Docs](https://supabase.com/docs)
- [Supabase Discord](https://discord.supabase.com)
