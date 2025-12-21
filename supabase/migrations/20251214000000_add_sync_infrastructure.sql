-- Migration: Add sync infrastructure for server-generated ID architecture
-- This adds idempotency key tracking and a change log for incremental sync

-- ============================================================================
-- Idempotency Keys Table
-- ============================================================================
-- Stores responses from create operations to ensure exactly-once semantics.
-- If a client retries with the same Idempotency-Key, we return the cached response.

CREATE TABLE IF NOT EXISTS public.idempotency_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,                                          -- Client-provided idempotency key (UUID)
    route TEXT NOT NULL,                                        -- HTTP method + path (e.g., "POST /api/v1/events")
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    request_hash TEXT,                                          -- Optional: hash of request body for validation
    response_body JSONB NOT NULL,                               -- Cached response to return on retry
    status_code INTEGER NOT NULL,                               -- HTTP status code of original response
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

    -- Unique constraint: same key + route + user = same operation
    CONSTRAINT idempotency_keys_unique UNIQUE (key, route, user_id)
);

-- Index for fast lookup during idempotency check
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_lookup
    ON public.idempotency_keys(key, route, user_id);

-- Index for cleanup job (expire old keys after 24 hours)
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_created_at
    ON public.idempotency_keys(created_at);

-- RLS: Users can only see their own idempotency keys (though they typically won't query this)
ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own idempotency keys"
    ON public.idempotency_keys FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage idempotency keys"
    ON public.idempotency_keys FOR ALL
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- Change Log Table
-- ============================================================================
-- Append-only log of all entity changes. Clients use this for incremental sync.
-- The `id` column is a monotonically increasing BIGSERIAL, used as the cursor.

CREATE TABLE IF NOT EXISTS public.change_log (
    id BIGSERIAL PRIMARY KEY,                                   -- Monotonic cursor for sync
    entity_type TEXT NOT NULL,                                  -- 'event', 'event_type', 'geofence', 'property_definition'
    operation TEXT NOT NULL,                                    -- 'create', 'update', 'delete'
    entity_id UUID NOT NULL,                                    -- ID of the affected entity
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    data JSONB,                                                 -- Full entity data for create/update (null for delete)
    deleted_at TIMESTAMP WITH TIME ZONE,                        -- Set for delete operations
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

    -- Validate operation values
    CONSTRAINT change_log_operation_check
        CHECK (operation IN ('create', 'update', 'delete')),

    -- Validate entity_type values
    CONSTRAINT change_log_entity_type_check
        CHECK (entity_type IN ('event', 'event_type', 'geofence', 'property_definition'))
);

-- Primary index for incremental sync: fetch changes for a user since cursor
CREATE INDEX IF NOT EXISTS idx_change_log_sync
    ON public.change_log(user_id, id);

-- Index for looking up changes by entity (useful for debugging/auditing)
CREATE INDEX IF NOT EXISTS idx_change_log_entity
    ON public.change_log(entity_type, entity_id);

-- Index for cleanup/archival by date
CREATE INDEX IF NOT EXISTS idx_change_log_created_at
    ON public.change_log(created_at);

-- RLS: Users can only see their own change log entries
ALTER TABLE public.change_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own change log"
    ON public.change_log FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage change log"
    ON public.change_log FOR ALL
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- Helper function to append to change log
-- ============================================================================
-- Called by repositories after successful create/update/delete operations

CREATE OR REPLACE FUNCTION public.append_change_log(
    p_entity_type TEXT,
    p_operation TEXT,
    p_entity_id UUID,
    p_user_id UUID,
    p_data JSONB DEFAULT NULL,
    p_deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    v_change_id BIGINT;
BEGIN
    INSERT INTO public.change_log (entity_type, operation, entity_id, user_id, data, deleted_at)
    VALUES (p_entity_type, p_operation, p_entity_id, p_user_id, p_data, p_deleted_at)
    RETURNING id INTO v_change_id;

    RETURN v_change_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users (will be called via service role)
GRANT EXECUTE ON FUNCTION public.append_change_log TO authenticated;
GRANT EXECUTE ON FUNCTION public.append_change_log TO service_role;

-- ============================================================================
-- Cleanup function for expired idempotency keys (run via cron or manually)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cleanup_expired_idempotency_keys(
    p_max_age_hours INTEGER DEFAULT 24
) RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM public.idempotency_keys
    WHERE created_at < NOW() - (p_max_age_hours || ' hours')::INTERVAL;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.cleanup_expired_idempotency_keys TO service_role;

-- ============================================================================
-- Comments for documentation
-- ============================================================================

COMMENT ON TABLE public.idempotency_keys IS 'Stores idempotency keys for exactly-once create semantics. Keys expire after 24 hours.';
COMMENT ON TABLE public.change_log IS 'Append-only log of all entity changes for incremental sync. The id column is the cursor.';
COMMENT ON FUNCTION public.append_change_log IS 'Appends an entry to the change log. Called after successful entity mutations.';
COMMENT ON FUNCTION public.cleanup_expired_idempotency_keys IS 'Removes idempotency keys older than the specified hours (default 24).';
