-- Add onboarding status tracking per user
-- This migration adds:
-- 1. onboarding_status table for storing user onboarding completion state
-- 2. RLS policies to ensure users can only access their own data
-- 3. Trigger for automatic updated_at timestamp

-- Create onboarding_status table
-- NOTE: user_id is the PRIMARY KEY (not a separate id column)
-- This enforces one onboarding status record per user
CREATE TABLE IF NOT EXISTS public.onboarding_status (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Overall completion flag
    completed BOOLEAN NOT NULL DEFAULT FALSE,

    -- Step completion timestamps (nullable - null means not yet completed)
    welcome_completed_at TIMESTAMP WITH TIME ZONE,
    auth_completed_at TIMESTAMP WITH TIME ZONE,
    permissions_completed_at TIMESTAMP WITH TIME ZONE,

    -- Notification permission tracking
    notifications_status TEXT,
    notifications_completed_at TIMESTAMP WITH TIME ZONE,

    -- HealthKit permission tracking
    healthkit_status TEXT,
    healthkit_completed_at TIMESTAMP WITH TIME ZONE,

    -- Location permission tracking
    location_status TEXT,
    location_completed_at TIMESTAMP WITH TIME ZONE,

    -- Standard timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Constraints for valid permission status values
    -- Valid values: 'granted', 'denied', 'skipped', 'not_requested'
    CONSTRAINT check_notifications_status
        CHECK (notifications_status IS NULL OR notifications_status IN ('granted', 'denied', 'skipped', 'not_requested')),
    CONSTRAINT check_healthkit_status
        CHECK (healthkit_status IS NULL OR healthkit_status IN ('granted', 'denied', 'skipped', 'not_requested')),
    CONSTRAINT check_location_status
        CHECK (location_status IS NULL OR location_status IN ('granted', 'denied', 'skipped', 'not_requested'))
);

-- Enable Row Level Security
ALTER TABLE public.onboarding_status ENABLE ROW LEVEL SECURITY;

-- RLS Policies - users can only access their own onboarding status

CREATE POLICY "Users can view own onboarding status"
    ON public.onboarding_status FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own onboarding status"
    ON public.onboarding_status FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own onboarding status"
    ON public.onboarding_status FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own onboarding status"
    ON public.onboarding_status FOR DELETE
    USING (auth.uid() = user_id);

-- Trigger for automatic updated_at timestamp
-- Uses existing update_updated_at_column() function
CREATE TRIGGER update_onboarding_status_updated_at
    BEFORE UPDATE ON public.onboarding_status
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Grant permissions to authenticated users and service role
GRANT ALL ON public.onboarding_status TO authenticated;
GRANT ALL ON public.onboarding_status TO service_role;

-- Documentation comments
COMMENT ON TABLE public.onboarding_status IS 'Tracks user onboarding completion status and permission choices';
COMMENT ON COLUMN public.onboarding_status.user_id IS 'User ID from auth.users - also serves as primary key (one record per user)';
COMMENT ON COLUMN public.onboarding_status.completed IS 'Whether the user has completed the entire onboarding flow';
COMMENT ON COLUMN public.onboarding_status.welcome_completed_at IS 'Timestamp when user completed the welcome step';
COMMENT ON COLUMN public.onboarding_status.auth_completed_at IS 'Timestamp when user completed the authentication step';
COMMENT ON COLUMN public.onboarding_status.permissions_completed_at IS 'Timestamp when user completed the permissions step';
COMMENT ON COLUMN public.onboarding_status.notifications_status IS 'Push notification permission status: granted, denied, skipped, or not_requested';
COMMENT ON COLUMN public.onboarding_status.notifications_completed_at IS 'Timestamp when user made their notifications permission choice';
COMMENT ON COLUMN public.onboarding_status.healthkit_status IS 'HealthKit permission status: granted, denied, skipped, or not_requested';
COMMENT ON COLUMN public.onboarding_status.healthkit_completed_at IS 'Timestamp when user made their HealthKit permission choice';
COMMENT ON COLUMN public.onboarding_status.location_status IS 'Location permission status: granted, denied, skipped, or not_requested';
COMMENT ON COLUMN public.onboarding_status.location_completed_at IS 'Timestamp when user made their location permission choice';
