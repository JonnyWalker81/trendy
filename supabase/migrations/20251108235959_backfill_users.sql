-- Backfill existing auth.users into public.users
-- This handles users created before the trigger was set up

INSERT INTO public.users (id, email, created_at, updated_at)
SELECT
    id,
    email,
    created_at,
    created_at as updated_at
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.users)
ON CONFLICT (id) DO NOTHING;

-- Ensure the trigger is properly set up
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
