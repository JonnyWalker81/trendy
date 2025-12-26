-- Migration: Add UUIDv7 support for time-ordered IDs
-- This migration:
-- 1. Creates a generate_uuidv7() function following RFC 9562
-- 2. Updates all table defaults to use UUIDv7 for new records
--
-- Benefits of UUIDv7:
-- - Time-ordered: Natural chronological sorting by ID
-- - Better index performance: B-tree indexes work better with sequential IDs
-- - Debugging visibility: Creation time embedded in first 48 bits
-- - Future-proofing: Industry moving toward UUIDv7 (PostgreSQL 18 has native support)
--
-- Backward Compatibility:
-- - Existing UUIDv4 records remain valid
-- - UUIDv4 and UUIDv7 coexist seamlessly (both are valid UUID type)
-- - All application code treats IDs as opaque strings (no changes needed)

-- ============================================================================
-- UUIDv7 Generator Function
-- ============================================================================
-- Creates UUIDv7 values per RFC 9562 specification:
-- - Bytes 0-5: 48-bit Unix timestamp in milliseconds (big-endian)
-- - Byte 6: version nibble (0111) + 4 bits of random
-- - Byte 7: 8 bits of random
-- - Byte 8: variant nibble (10) + 6 bits of random
-- - Bytes 9-15: 48 bits of random

CREATE OR REPLACE FUNCTION public.generate_uuidv7()
RETURNS uuid AS $$
DECLARE
    v_time timestamp with time zone;
    v_unix_ms bigint;
    v_rand bytea;
    v_uuid bytea;
BEGIN
    -- Get current timestamp in milliseconds since Unix epoch
    v_time := clock_timestamp();
    v_unix_ms := (EXTRACT(EPOCH FROM v_time) * 1000)::bigint;

    -- Generate 10 bytes of cryptographically secure random data
    v_rand := gen_random_bytes(10);

    -- Build UUIDv7 byte sequence:
    v_uuid :=
        -- Bytes 0-5: 48-bit timestamp (big-endian milliseconds)
        substring(int8send(v_unix_ms) from 3 for 6) ||
        -- Byte 6: Version 7 (0111xxxx) + high 4 bits of rand
        set_byte(substring(v_rand from 1 for 1), 0,
            (get_byte(v_rand, 0) & x'0F'::int) | x'70'::int) ||
        -- Byte 7: 8 bits of random
        substring(v_rand from 2 for 1) ||
        -- Byte 8: Variant (10xxxxxx) + high 6 bits of rand
        set_byte(substring(v_rand from 3 for 1), 0,
            (get_byte(v_rand, 2) & x'3F'::int) | x'80'::int) ||
        -- Bytes 9-15: 56 bits of random
        substring(v_rand from 4 for 7);

    RETURN encode(v_uuid, 'hex')::uuid;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.generate_uuidv7 TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_uuidv7 TO service_role;

COMMENT ON FUNCTION public.generate_uuidv7 IS 'Generates UUIDv7 values per RFC 9562. Time-ordered with embedded millisecond timestamp.';

-- ============================================================================
-- Update Table Defaults
-- ============================================================================
-- Change all UUID primary key defaults from gen_random_uuid() to generate_uuidv7()
-- These are instantaneous operations (no table rewrite)

-- Core entities
ALTER TABLE public.event_types
    ALTER COLUMN id SET DEFAULT public.generate_uuidv7();

ALTER TABLE public.events
    ALTER COLUMN id SET DEFAULT public.generate_uuidv7();

ALTER TABLE public.property_definitions
    ALTER COLUMN id SET DEFAULT public.generate_uuidv7();

ALTER TABLE public.geofences
    ALTER COLUMN id SET DEFAULT public.generate_uuidv7();

-- Intelligence layer
ALTER TABLE public.daily_aggregates
    ALTER COLUMN id SET DEFAULT public.generate_uuidv7();

ALTER TABLE public.insights
    ALTER COLUMN id SET DEFAULT public.generate_uuidv7();

ALTER TABLE public.streaks
    ALTER COLUMN id SET DEFAULT public.generate_uuidv7();

-- Sync infrastructure
ALTER TABLE public.idempotency_keys
    ALTER COLUMN id SET DEFAULT public.generate_uuidv7();

-- Note: change_log.id intentionally uses BIGSERIAL for monotonic cursor ordering
-- Note: users.id comes from auth.users and is not auto-generated here

-- ============================================================================
-- Verification
-- ============================================================================
-- Test that the function works correctly

DO $$
DECLARE
    v_uuid1 uuid;
    v_uuid2 uuid;
BEGIN
    -- Generate two UUIDs
    v_uuid1 := public.generate_uuidv7();
    PERFORM pg_sleep(0.001); -- Wait 1ms
    v_uuid2 := public.generate_uuidv7();

    -- Verify version nibble is 7 (check 7th character is '7')
    IF substring(v_uuid1::text from 15 for 1) != '7' THEN
        RAISE EXCEPTION 'UUIDv7 version nibble incorrect: %', v_uuid1;
    END IF;

    -- Verify time ordering (uuid2 should be greater due to later timestamp)
    IF v_uuid2 <= v_uuid1 THEN
        RAISE EXCEPTION 'UUIDv7 time ordering failed: % should be > %', v_uuid2, v_uuid1;
    END IF;

    RAISE NOTICE 'UUIDv7 verification passed. Sample: %', v_uuid1;
END;
$$;
