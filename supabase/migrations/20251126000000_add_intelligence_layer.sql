-- Add intelligence layer for automated insights, correlations, and streak tracking
-- This migration adds:
-- 1. insights table for caching computed insights
-- 2. daily_aggregates table for pre-computed daily event statistics
-- 3. streaks table for tracking current and longest streaks per event type

-- Create daily_aggregates table (needed for correlation calculations)
CREATE TABLE IF NOT EXISTS public.daily_aggregates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    event_type_id UUID NOT NULL REFERENCES public.event_types(id) ON DELETE CASCADE,
    event_count INT NOT NULL DEFAULT 0,
    total_duration_seconds DOUBLE PRECISION,
    avg_numeric_value DOUBLE PRECISION,
    property_aggregates JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, date, event_type_id)
);

-- Create insights table (caches computed insights with TTL)
CREATE TABLE IF NOT EXISTS public.insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    insight_type TEXT NOT NULL,
    category TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    event_type_a_id UUID REFERENCES public.event_types(id) ON DELETE CASCADE,
    event_type_b_id UUID REFERENCES public.event_types(id) ON DELETE CASCADE,
    property_key TEXT,
    metric_value DOUBLE PRECISION NOT NULL,
    p_value DOUBLE PRECISION,
    sample_size INT NOT NULL,
    confidence TEXT NOT NULL DEFAULT 'medium',
    direction TEXT NOT NULL DEFAULT 'neutral',
    metadata JSONB DEFAULT '{}',
    computed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create streaks table
CREATE TABLE IF NOT EXISTS public.streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    event_type_id UUID NOT NULL REFERENCES public.event_types(id) ON DELETE CASCADE,
    streak_type TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    length INT NOT NULL DEFAULT 0,
    is_active BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, event_type_id, streak_type)
);

-- Add check constraints
ALTER TABLE public.insights
ADD CONSTRAINT check_insight_type
CHECK (insight_type IN ('correlation', 'pattern', 'streak', 'summary'));

ALTER TABLE public.insights
ADD CONSTRAINT check_insight_category
CHECK (category IN ('cross_event', 'property', 'time_of_day', 'day_of_week', 'weekly', 'streak'));

ALTER TABLE public.insights
ADD CONSTRAINT check_insight_confidence
CHECK (confidence IN ('high', 'medium', 'low'));

ALTER TABLE public.insights
ADD CONSTRAINT check_insight_direction
CHECK (direction IN ('positive', 'negative', 'neutral'));

ALTER TABLE public.streaks
ADD CONSTRAINT check_streak_type
CHECK (streak_type IN ('current', 'longest'));

-- Indexes for daily_aggregates
CREATE INDEX IF NOT EXISTS idx_daily_aggregates_user_id
ON public.daily_aggregates(user_id);

CREATE INDEX IF NOT EXISTS idx_daily_aggregates_user_date
ON public.daily_aggregates(user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_daily_aggregates_user_event_type
ON public.daily_aggregates(user_id, event_type_id);

CREATE INDEX IF NOT EXISTS idx_daily_aggregates_date_range
ON public.daily_aggregates(user_id, date, event_type_id);

-- Indexes for insights
CREATE INDEX IF NOT EXISTS idx_insights_user_id
ON public.insights(user_id);

CREATE INDEX IF NOT EXISTS idx_insights_user_type
ON public.insights(user_id, insight_type);

CREATE INDEX IF NOT EXISTS idx_insights_valid_until
ON public.insights(valid_until);

CREATE INDEX IF NOT EXISTS idx_insights_user_valid
ON public.insights(user_id, valid_until);

-- Indexes for streaks
CREATE INDEX IF NOT EXISTS idx_streaks_user_id
ON public.streaks(user_id);

CREATE INDEX IF NOT EXISTS idx_streaks_user_event
ON public.streaks(user_id, event_type_id);

CREATE INDEX IF NOT EXISTS idx_streaks_active
ON public.streaks(user_id, is_active) WHERE is_active = true;

-- Row Level Security

-- Enable RLS
ALTER TABLE public.daily_aggregates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.streaks ENABLE ROW LEVEL SECURITY;

-- daily_aggregates policies
CREATE POLICY "Users can view own daily_aggregates"
    ON public.daily_aggregates FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own daily_aggregates"
    ON public.daily_aggregates FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own daily_aggregates"
    ON public.daily_aggregates FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own daily_aggregates"
    ON public.daily_aggregates FOR DELETE
    USING (auth.uid() = user_id);

-- insights policies
CREATE POLICY "Users can view own insights"
    ON public.insights FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own insights"
    ON public.insights FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own insights"
    ON public.insights FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own insights"
    ON public.insights FOR DELETE
    USING (auth.uid() = user_id);

-- streaks policies
CREATE POLICY "Users can view own streaks"
    ON public.streaks FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own streaks"
    ON public.streaks FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own streaks"
    ON public.streaks FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own streaks"
    ON public.streaks FOR DELETE
    USING (auth.uid() = user_id);

-- Triggers for updated_at

-- daily_aggregates updated_at trigger
CREATE TRIGGER update_daily_aggregates_updated_at
    BEFORE UPDATE ON public.daily_aggregates
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- streaks updated_at trigger
CREATE TRIGGER update_streaks_updated_at
    BEFORE UPDATE ON public.streaks
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Add comments for documentation
COMMENT ON TABLE public.daily_aggregates IS 'Pre-aggregated daily event statistics for efficient correlation calculations';
COMMENT ON COLUMN public.daily_aggregates.date IS 'The date for which events are aggregated';
COMMENT ON COLUMN public.daily_aggregates.event_count IS 'Number of events of this type on this date';
COMMENT ON COLUMN public.daily_aggregates.total_duration_seconds IS 'Sum of all event durations in seconds (if applicable)';
COMMENT ON COLUMN public.daily_aggregates.avg_numeric_value IS 'Average of numeric property values for this date';
COMMENT ON COLUMN public.daily_aggregates.property_aggregates IS 'JSON object with per-property aggregate statistics';

COMMENT ON TABLE public.insights IS 'Cached computed insights with TTL for display to users';
COMMENT ON COLUMN public.insights.insight_type IS 'Type of insight: correlation, pattern, streak, or summary';
COMMENT ON COLUMN public.insights.category IS 'Category: cross_event, property, time_of_day, day_of_week, weekly, streak';
COMMENT ON COLUMN public.insights.title IS 'Human-readable insight title (e.g., "Exercise and Sleep")';
COMMENT ON COLUMN public.insights.description IS 'Full insight description (e.g., "You sleep 23% better on days you exercise")';
COMMENT ON COLUMN public.insights.metric_value IS 'Primary metric value (correlation coefficient, percentage, count)';
COMMENT ON COLUMN public.insights.p_value IS 'Statistical significance p-value for correlations';
COMMENT ON COLUMN public.insights.sample_size IS 'Number of data points used to compute this insight';
COMMENT ON COLUMN public.insights.confidence IS 'Confidence level: high, medium, or low';
COMMENT ON COLUMN public.insights.direction IS 'Direction: positive, negative, or neutral';
COMMENT ON COLUMN public.insights.valid_until IS 'Cache expiry timestamp - recompute after this time';

COMMENT ON TABLE public.streaks IS 'Tracks current and longest streaks per event type per user';
COMMENT ON COLUMN public.streaks.streak_type IS 'Type: current (ongoing) or longest (historical best)';
COMMENT ON COLUMN public.streaks.start_date IS 'First day of the streak';
COMMENT ON COLUMN public.streaks.end_date IS 'Last day of the streak (NULL for current active streaks)';
COMMENT ON COLUMN public.streaks.length IS 'Number of consecutive days';
COMMENT ON COLUMN public.streaks.is_active IS 'Whether this is the currently active streak';
