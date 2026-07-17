-- ============================================================================
-- FIX Issue-3a: Backfill missing avatar_outfits rows
-- ============================================================================
-- The handle_new_user() trigger already creates avatar_outfits rows for NEW
-- signups.  This script catches any EXISTING users who signed up before the
-- trigger was installed or when the avatar_outfits table didn't exist yet.
-- Safe to run multiple times (uses ON CONFLICT DO NOTHING).
-- ============================================================================

INSERT INTO public.avatar_outfits (
    user_id,
    head_color,
    torso_color,
    left_arm_color,
    right_arm_color,
    left_leg_color,
    right_leg_color,
    equipped_items,
    body_type,
    created_at,
    updated_at
)
SELECT
    p.id,
    '#F5CC33',   -- default yellow head
    '#0D66B3',   -- default blue torso
    '#F5CC33',   -- default yellow left arm
    '#F5CC33',   -- default yellow right arm
    '#A6CC33',   -- default green left leg
    '#A6CC33',   -- default green right leg
    '[]'::jsonb,
    'R6',
    timezone('utc', now()),
    timezone('utc', now())
FROM public.profiles p
WHERE NOT EXISTS (
    SELECT 1
    FROM public.avatar_outfits ao
    WHERE ao.user_id = p.id
)
ON CONFLICT (user_id) DO NOTHING;
