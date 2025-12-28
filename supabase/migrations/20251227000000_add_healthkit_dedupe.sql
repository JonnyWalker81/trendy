-- Migration: Add HealthKit deduplication infrastructure
-- This migration adds server-side idempotency for HealthKit imports

-- Step 1: Add missing HealthKit columns (referenced in code but never created!)
ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS healthkit_sample_id TEXT,
ADD COLUMN IF NOT EXISTS healthkit_category TEXT;

COMMENT ON COLUMN public.events.healthkit_sample_id IS
    'Client-generated unique identifier for HealthKit samples (e.g., "steps-2025-01-15", workout UUID)';
COMMENT ON COLUMN public.events.healthkit_category IS
    'HealthKit category type (e.g., "HKQuantityTypeIdentifierStepCount", "HKWorkoutActivityTypeRunning")';

-- Step 2: Add partial unique index for HealthKit deduplication
-- This is the canonical dedupe key for all HealthKit imports
-- Multiple imports with same sample_id will upsert instead of conflict
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_healthkit_dedupe
ON public.events (user_id, healthkit_sample_id)
WHERE source_type = 'healthkit' AND healthkit_sample_id IS NOT NULL;

-- Step 3: Modify timestamp constraint to exclude HealthKit
-- The current UNIQUE(user_id, event_type_id, timestamp) conflicts with HealthKit because:
--   - Multiple workouts can start at the same second
--   - Sleep segments from different sources may overlap
--   - Editing a sample in Apple Health changes its UUID but keeps the date

-- Drop the existing full unique constraint
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS unique_user_event_type_timestamp;

-- Recreate as partial unique index that EXCLUDES HealthKit
-- Manual/imported/geofence events still have timestamp uniqueness
-- HealthKit events use healthkit_sample_id for uniqueness instead
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_manual_dedupe
ON public.events (user_id, event_type_id, timestamp)
WHERE source_type != 'healthkit';

-- Add comment explaining the constraint design
COMMENT ON INDEX idx_events_healthkit_dedupe IS
    'Ensures HealthKit events are unique by sample ID within a user. Enables idempotent imports.';
COMMENT ON INDEX idx_events_manual_dedupe IS
    'Ensures non-HealthKit events are unique by event type and timestamp within a user.';
