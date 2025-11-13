-- Add custom properties support for events
-- This migration adds:
-- 1. property_definitions table for defining property schemas on event types
-- 2. properties JSONB column on events table for storing actual property values
-- 3. Support for multiple property types: text, number, boolean, date, select, duration, url, email

-- Create property_definitions table
CREATE TABLE IF NOT EXISTS public.property_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type_id UUID NOT NULL REFERENCES public.event_types(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    label TEXT NOT NULL,
    property_type TEXT NOT NULL,
    options JSONB,
    default_value JSONB,
    display_order INTEGER DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    UNIQUE(event_type_id, key)
);

-- Add check constraint to ensure property_type is valid
ALTER TABLE public.property_definitions
ADD CONSTRAINT check_property_type
CHECK (property_type IN ('text', 'number', 'boolean', 'date', 'select', 'duration', 'url', 'email'));

-- Add properties column to events table
ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS properties JSONB DEFAULT '{}'::jsonb NOT NULL;

-- Indexes for property_definitions
CREATE INDEX IF NOT EXISTS idx_property_definitions_event_type_id
ON public.property_definitions(event_type_id);

CREATE INDEX IF NOT EXISTS idx_property_definitions_user_id
ON public.property_definitions(user_id);

CREATE INDEX IF NOT EXISTS idx_property_definitions_display_order
ON public.property_definitions(event_type_id, display_order);

-- GIN index for JSONB properties on events (enables efficient querying)
CREATE INDEX IF NOT EXISTS idx_events_properties
ON public.events USING GIN (properties);

-- Row Level Security for property_definitions

-- Enable RLS
ALTER TABLE public.property_definitions ENABLE ROW LEVEL SECURITY;

-- Property Definitions policies
CREATE POLICY "Users can view own property definitions"
    ON public.property_definitions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own property definitions"
    ON public.property_definitions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own property definitions"
    ON public.property_definitions FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own property definitions"
    ON public.property_definitions FOR DELETE
    USING (auth.uid() = user_id);

-- Triggers for property_definitions

-- Trigger for updated_at
CREATE TRIGGER update_property_definitions_updated_at
    BEFORE UPDATE ON public.property_definitions
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Trigger for updated_by
CREATE TRIGGER set_property_definitions_updated_by
    BEFORE INSERT OR UPDATE ON public.property_definitions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_by();

-- Add comments for documentation
COMMENT ON TABLE public.property_definitions IS 'Defines custom property schemas for event types';
COMMENT ON COLUMN public.property_definitions.key IS 'Unique key for the property within the event type (e.g., "duration", "intensity")';
COMMENT ON COLUMN public.property_definitions.label IS 'Human-readable label displayed in UI (e.g., "Duration", "Intensity Level")';
COMMENT ON COLUMN public.property_definitions.property_type IS 'Data type: text, number, boolean, date, select, duration, url, email';
COMMENT ON COLUMN public.property_definitions.options IS 'For select type: array of option values (e.g., ["Low", "Medium", "High"])';
COMMENT ON COLUMN public.property_definitions.default_value IS 'Optional default value for the property';
COMMENT ON COLUMN public.property_definitions.display_order IS 'Order in which properties are displayed in UI (lower numbers first)';

COMMENT ON COLUMN public.events.properties IS 'Custom property values stored as JSONB: {"key": {"type": "text", "value": "example"}}';
