-- Add missing event fields to match iOS app functionality
-- This migration adds support for all-day events, calendar sync, and event duration

-- Add new columns to events table
ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS is_all_day BOOLEAN DEFAULT false NOT NULL,
ADD COLUMN IF NOT EXISTS end_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS source_type TEXT DEFAULT 'manual' NOT NULL,
ADD COLUMN IF NOT EXISTS external_id TEXT,
ADD COLUMN IF NOT EXISTS original_title TEXT;

-- Add check constraint to ensure source_type is valid
ALTER TABLE public.events
ADD CONSTRAINT check_source_type
CHECK (source_type IN ('manual', 'imported'));

-- Add index for querying by external_id (for calendar sync)
CREATE INDEX IF NOT EXISTS idx_events_external_id ON public.events(external_id) WHERE external_id IS NOT NULL;

-- Add index for querying all-day events
CREATE INDEX IF NOT EXISTS idx_events_is_all_day ON public.events(is_all_day) WHERE is_all_day = true;

-- Add comment to document the new fields
COMMENT ON COLUMN public.events.is_all_day IS 'True if this is an all-day event (no specific time)';
COMMENT ON COLUMN public.events.end_date IS 'Optional end date for all-day or multi-day events';
COMMENT ON COLUMN public.events.source_type IS 'Origin of the event: manual (user created) or imported (from calendar)';
COMMENT ON COLUMN public.events.external_id IS 'External identifier for calendar sync (e.g., Calendar event ID)';
COMMENT ON COLUMN public.events.original_title IS 'Original title from imported calendar event';
