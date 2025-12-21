-- Migration: Add unique constraint on events to prevent duplicates
-- This ensures only one event can exist per user + event_type + timestamp combination

-- First, clean up existing duplicates by keeping only the oldest record (by created_at)
-- This uses a CTE to identify duplicates and delete all but the first one
WITH duplicates AS (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY user_id, event_type_id, timestamp
               ORDER BY created_at ASC
           ) as row_num
    FROM events
)
DELETE FROM events
WHERE id IN (
    SELECT id FROM duplicates WHERE row_num > 1
);

-- Add unique constraint to prevent future duplicates
-- A user cannot have two events of the same type at the exact same timestamp
ALTER TABLE events
ADD CONSTRAINT unique_user_event_type_timestamp
UNIQUE (user_id, event_type_id, timestamp);

-- Add comment explaining the constraint
COMMENT ON CONSTRAINT unique_user_event_type_timestamp ON events IS
    'Prevents duplicate events: same user, event type, and timestamp combination must be unique';
