-- Add geofence support for automatic location-based event tracking
-- This migration adds:
-- 1. geofences table for storing user-defined geographic regions
-- 2. Location fields to events table for geofence-triggered events
-- 3. Update source_type constraint to include 'geofence'

-- Create geofences table
CREATE TABLE IF NOT EXISTS public.geofences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius DOUBLE PRECISION NOT NULL,
    event_type_entry_id UUID REFERENCES public.event_types(id) ON DELETE SET NULL,
    event_type_exit_id UUID REFERENCES public.event_types(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    notify_on_entry BOOLEAN DEFAULT false NOT NULL,
    notify_on_exit BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    UNIQUE(user_id, name)
);

-- Add location fields to events table
ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS geofence_id UUID REFERENCES public.geofences(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS location_latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS location_longitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS location_name TEXT;

-- Update source_type constraint to include 'geofence'
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS check_source_type;
ALTER TABLE public.events
ADD CONSTRAINT check_source_type
CHECK (source_type IN ('manual', 'imported', 'geofence'));

-- Add check constraint to ensure radius is reasonable (50m to 10km)
ALTER TABLE public.geofences
ADD CONSTRAINT check_radius_range
CHECK (radius >= 50 AND radius <= 10000);

-- Add check constraint to ensure valid coordinates
ALTER TABLE public.geofences
ADD CONSTRAINT check_latitude_range
CHECK (latitude >= -90 AND latitude <= 90);

ALTER TABLE public.geofences
ADD CONSTRAINT check_longitude_range
CHECK (longitude >= -180 AND longitude <= 180);

-- Indexes for geofences
CREATE INDEX IF NOT EXISTS idx_geofences_user_id
ON public.geofences(user_id);

CREATE INDEX IF NOT EXISTS idx_geofences_is_active
ON public.geofences(user_id, is_active) WHERE is_active = true;

-- Indexes for events with location data
CREATE INDEX IF NOT EXISTS idx_events_geofence_id
ON public.events(geofence_id) WHERE geofence_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_events_location
ON public.events(location_latitude, location_longitude) WHERE location_latitude IS NOT NULL;

-- Row Level Security for geofences

-- Enable RLS
ALTER TABLE public.geofences ENABLE ROW LEVEL SECURITY;

-- Geofences policies
CREATE POLICY "Users can view own geofences"
    ON public.geofences FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own geofences"
    ON public.geofences FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own geofences"
    ON public.geofences FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own geofences"
    ON public.geofences FOR DELETE
    USING (auth.uid() = user_id);

-- Triggers for geofences

-- Trigger for updated_at
CREATE TRIGGER update_geofences_updated_at
    BEFORE UPDATE ON public.geofences
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Trigger for updated_by
CREATE TRIGGER set_geofences_updated_by
    BEFORE INSERT OR UPDATE ON public.geofences
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_by();

-- Add comments for documentation
COMMENT ON TABLE public.geofences IS 'User-defined geographic regions for automatic event tracking';
COMMENT ON COLUMN public.geofences.name IS 'Human-readable name for the location (e.g., "Home", "Office", "Gym")';
COMMENT ON COLUMN public.geofences.latitude IS 'Geographic latitude in decimal degrees (-90 to 90)';
COMMENT ON COLUMN public.geofences.longitude IS 'Geographic longitude in decimal degrees (-180 to 180)';
COMMENT ON COLUMN public.geofences.radius IS 'Geofence radius in meters (50m to 10km)';
COMMENT ON COLUMN public.geofences.event_type_entry_id IS 'Event type to create when user enters this geofence';
COMMENT ON COLUMN public.geofences.event_type_exit_id IS 'Event type to create when user exits this geofence (currently unused)';
COMMENT ON COLUMN public.geofences.is_active IS 'Whether this geofence is actively being monitored';
COMMENT ON COLUMN public.geofences.notify_on_entry IS 'Send push notification when user enters this geofence';
COMMENT ON COLUMN public.geofences.notify_on_exit IS 'Send push notification when user exits this geofence';

COMMENT ON COLUMN public.events.geofence_id IS 'Reference to the geofence that triggered this event (if source_type is geofence)';
COMMENT ON COLUMN public.events.location_latitude IS 'Latitude where the geofence event was triggered';
COMMENT ON COLUMN public.events.location_longitude IS 'Longitude where the geofence event was triggered';
COMMENT ON COLUMN public.events.location_name IS 'Human-readable location name from the geofence';
