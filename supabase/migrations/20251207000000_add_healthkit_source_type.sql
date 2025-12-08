-- Add healthkit as a valid source_type for events
-- This enables syncing of HealthKit-imported events from iOS

-- Update source_type constraint to include 'healthkit'
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS check_source_type;
ALTER TABLE public.events
ADD CONSTRAINT check_source_type
CHECK (source_type IN ('manual', 'imported', 'geofence', 'healthkit'));

-- Update the comment to document the new source type
COMMENT ON COLUMN public.events.source_type IS 'Origin of the event: manual (user created), imported (from calendar), geofence (location-based), or healthkit (from Apple HealthKit)';
