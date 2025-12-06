-- Add iOS region identifier column to geofences table
-- This stores the CLLocationManager region identifier used on iOS devices
-- for easy lookup during geofence entry/exit events

ALTER TABLE public.geofences
ADD COLUMN IF NOT EXISTS ios_region_identifier TEXT;

-- Index for fast lookup by iOS region identifier
CREATE INDEX IF NOT EXISTS idx_geofences_ios_region_identifier
ON public.geofences(ios_region_identifier)
WHERE ios_region_identifier IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN public.geofences.ios_region_identifier IS 'CLLocationManager region identifier used on iOS devices for geofence monitoring';
