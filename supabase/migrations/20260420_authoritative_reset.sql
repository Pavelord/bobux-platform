-- ============================================================================
-- FULL SUPABASE SQL SCHEMA -- Dedicated Authoritative WebSocket Stack
-- Safe to run in the Supabase SQL Editor or via `supabase db query --file`.
-- This script intentionally resets the multiplayer-facing data model so the
-- project starts from a clean slate with no legacy transport leftovers.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- STEP 0: REMOVE LEGACY OBJECTS AND DATA
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.handle_new_user_profile();
DROP FUNCTION IF EXISTS public.touch_updated_at();
DROP FUNCTION IF EXISTS public.cleanup_stale_active_servers();

DO $cleanup_cron$
DECLARE
	job_record RECORD;
BEGIN
	IF to_regclass('cron.job') IS NULL THEN
		RETURN;
	END IF;
	FOR job_record IN
		SELECT jobid
		FROM cron.job
		WHERE jobname IN (
			'cleanup-ghost-peers',
			'cleanup-active-servers'
		)
	LOOP
		PERFORM cron.unschedule(job_record.jobid);
	END LOOP;
EXCEPTION
	WHEN OTHERS THEN
		RAISE NOTICE 'Skipping pg_cron unschedule: %', SQLERRM;
END;
$cleanup_cron$;

DROP TABLE IF EXISTS public.webrtc_signaling CASCADE;
DROP TABLE IF EXISTS public.signaling CASCADE;
DROP TABLE IF EXISTS public.p2p_sessions CASCADE;
DROP TABLE IF EXISTS public.friends CASCADE;
DROP TABLE IF EXISTS public.friend_requests CASCADE;
DROP TABLE IF EXISTS public.friendships CASCADE;
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.avatar_outfits CASCADE;
DROP TABLE IF EXISTS public.catalog_items CASCADE;
DROP TABLE IF EXISTS public.active_servers CASCADE;
DROP TABLE IF EXISTS public.maps CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

DELETE FROM auth.users;

-- ============================================================================
-- STEP 1: SHARED HELPERS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
	NEW.updated_at = timezone('utc', now());
	RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 2: PROFILES
-- ============================================================================

CREATE TABLE public.profiles (
	id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
	username TEXT NOT NULL UNIQUE,
	status TEXT NOT NULL DEFAULT 'offline'
		CHECK (status IN ('offline', 'online', 'playing', 'studio', 'away')),
	current_game TEXT NOT NULL DEFAULT '',
	current_server_host TEXT NOT NULL DEFAULT '',
	current_server_ip TEXT NOT NULL DEFAULT '',
	current_server_port INTEGER NOT NULL DEFAULT 0,
	robux_balance INTEGER NOT NULL DEFAULT 0,
	tickets_balance INTEGER NOT NULL DEFAULT 0,
	join_date TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	about_text TEXT NOT NULL DEFAULT '',
	avatar_data JSONB NOT NULL DEFAULT '{"equipped":[]}'::jsonb,
	inventory_items JSONB NOT NULL DEFAULT '[]'::jsonb,
	created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX idx_profiles_status ON public.profiles(status);
CREATE INDEX idx_profiles_updated_at ON public.profiles(updated_at DESC);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profiles are viewable by everyone"
	ON public.profiles FOR SELECT
	USING (true);

CREATE POLICY "Users can insert their own profile"
	ON public.profiles FOR INSERT
	WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
	ON public.profiles FOR UPDATE
	USING (auth.uid() = id)
	WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can delete their own profile"
	ON public.profiles FOR DELETE
	USING (auth.uid() = id);

CREATE TRIGGER profiles_touch_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

-- Auto-create the public profile + avatar outfit row for every new auth user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	fallback_username TEXT;
BEGIN
	fallback_username := NULLIF(trim(COALESCE(NEW.raw_user_meta_data->>'username', '')), '');
	IF fallback_username IS NULL THEN
		fallback_username := 'player_' || left(replace(NEW.id::text, '-', ''), 8);
	END IF;

	INSERT INTO public.profiles (
		id,
		username,
		join_date,
		created_at,
		updated_at
	)
	VALUES (
		NEW.id,
		fallback_username,
		timezone('utc', now()),
		timezone('utc', now()),
		timezone('utc', now())
	)
	ON CONFLICT (id) DO NOTHING;

	INSERT INTO public.avatar_outfits (
		user_id,
		created_at,
		updated_at
	)
	VALUES (
		NEW.id,
		timezone('utc', now()),
		timezone('utc', now())
	)
	ON CONFLICT (user_id) DO NOTHING;

	RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 3: MAPS
-- ============================================================================

CREATE TABLE public.maps (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL,
	owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
	owner_name TEXT NOT NULL DEFAULT 'Builder',
	description TEXT NOT NULL DEFAULT '',
	thumbnail TEXT NOT NULL DEFAULT '',
	data JSONB NOT NULL DEFAULT '{}'::jsonb,
	cloud_version_id TEXT NOT NULL DEFAULT '',
	is_published BOOLEAN NOT NULL DEFAULT true,
	created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX idx_maps_owner_id ON public.maps(owner_id);
CREATE INDEX idx_maps_updated_at ON public.maps(updated_at DESC);

ALTER TABLE public.maps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Published maps are viewable by everyone"
	ON public.maps FOR SELECT
	USING (is_published OR auth.uid() = owner_id);

CREATE POLICY "Users can insert their own maps"
	ON public.maps FOR INSERT
	WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can update their own maps"
	ON public.maps FOR UPDATE
	USING (auth.uid() = owner_id)
	WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can delete their own maps"
	ON public.maps FOR DELETE
	USING (auth.uid() = owner_id);

CREATE TRIGGER maps_touch_updated_at
BEFORE UPDATE ON public.maps
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

-- ============================================================================
-- STEP 4: ACTIVE SERVERS
-- ============================================================================

CREATE TABLE public.active_servers (
	server_key TEXT PRIMARY KEY,
	room_id TEXT NOT NULL DEFAULT '',
	map_id TEXT NOT NULL DEFAULT 'classic',
	map_name TEXT NOT NULL DEFAULT 'Classic',
	cloud_version_id TEXT NOT NULL DEFAULT '',
	server_url TEXT NOT NULL DEFAULT '',
	ip TEXT NOT NULL DEFAULT '',
	port INTEGER NOT NULL DEFAULT 443,
	player_id TEXT NOT NULL DEFAULT '',
	host_user_id TEXT NOT NULL DEFAULT '',
	host_username TEXT NOT NULL DEFAULT 'Dedicated Server',
	transport TEXT NOT NULL DEFAULT 'websocket'
		CHECK (transport IN ('websocket')),
	is_host BOOLEAN NOT NULL DEFAULT true,
	players_count INTEGER NOT NULL DEFAULT 0 CHECK (players_count >= 0),
	max_players INTEGER NOT NULL DEFAULT 10 CHECK (max_players > 0),
	status TEXT NOT NULL DEFAULT 'active'
		CHECK (status IN ('active', 'closing')),
	last_seen BIGINT NOT NULL DEFAULT (extract(epoch from timezone('utc', now())))::bigint,
	last_seen_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	started_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX idx_active_servers_room_id ON public.active_servers(room_id);
CREATE INDEX idx_active_servers_status ON public.active_servers(status);
CREATE INDEX idx_active_servers_last_seen ON public.active_servers(last_seen DESC);
CREATE INDEX idx_active_servers_server_url ON public.active_servers(server_url);
CREATE INDEX idx_active_servers_host_user_id ON public.active_servers(host_user_id);

ALTER TABLE public.active_servers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active servers are viewable by everyone"
	ON public.active_servers FOR SELECT
	USING (true);

CREATE TRIGGER active_servers_touch_updated_at
BEFORE UPDATE ON public.active_servers
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

CREATE OR REPLACE FUNCTION public.cleanup_stale_active_servers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	deleted_rows INTEGER := 0;
BEGIN
	DELETE FROM public.active_servers
	WHERE last_seen < (extract(epoch from timezone('utc', now())) - 15)::bigint;

	GET DIAGNOSTICS deleted_rows = ROW_COUNT;
	RETURN deleted_rows;
END;
$$;

DO $schedule_cron$
BEGIN
	IF to_regclass('cron.job') IS NULL THEN
		RAISE NOTICE 'pg_cron is not available; skipping heartbeat cleanup schedule.';
		RETURN;
	END IF;

	PERFORM cron.schedule(
		'cleanup-active-servers',
		'10 seconds',
		$$select public.cleanup_stale_active_servers();$$
	);
EXCEPTION
	WHEN OTHERS THEN
		RAISE NOTICE 'Skipping pg_cron schedule: %', SQLERRM;
END;
$schedule_cron$;

-- ============================================================================
-- STEP 5: CATALOG + INVENTORY
-- ============================================================================

CREATE TABLE public.catalog_items (
	item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	name TEXT NOT NULL,
	category TEXT NOT NULL DEFAULT 'Accessories',
	type TEXT NOT NULL DEFAULT 'accessory',
	description TEXT NOT NULL DEFAULT '',
	creator_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
	price_robux INTEGER NOT NULL DEFAULT 0,
	price_tickets INTEGER NOT NULL DEFAULT 0,
	is_for_sale BOOLEAN NOT NULL DEFAULT true,
	is_limited BOOLEAN NOT NULL DEFAULT false,
	model_url TEXT NOT NULL DEFAULT '',
	thumbnail_url TEXT NOT NULL DEFAULT '',
	created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX idx_catalog_items_category ON public.catalog_items(category);
CREATE INDEX idx_catalog_items_type ON public.catalog_items(type);
CREATE INDEX idx_catalog_items_for_sale ON public.catalog_items(is_for_sale);

ALTER TABLE public.catalog_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Catalog items are viewable by everyone"
	ON public.catalog_items FOR SELECT
	USING (true);

CREATE TRIGGER catalog_items_touch_updated_at
BEFORE UPDATE ON public.catalog_items
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE public.inventory (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	item_id UUID NOT NULL REFERENCES public.catalog_items(item_id) ON DELETE CASCADE,
	source TEXT NOT NULL DEFAULT 'grant',
	acquired_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	UNIQUE (user_id, item_id)
);

CREATE INDEX idx_inventory_user_id ON public.inventory(user_id);
CREATE INDEX idx_inventory_item_id ON public.inventory(item_id);

ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own inventory"
	ON public.inventory FOR SELECT
	USING (auth.uid() = user_id);

-- ============================================================================
-- STEP 6: AVATAR OUTFITS
-- ============================================================================

CREATE TABLE public.avatar_outfits (
	user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
	head_color TEXT NOT NULL DEFAULT '#F5CC33',
	torso_color TEXT NOT NULL DEFAULT '#0D66B3',
	left_arm_color TEXT NOT NULL DEFAULT '#F5CC33',
	right_arm_color TEXT NOT NULL DEFAULT '#F5CC33',
	left_leg_color TEXT NOT NULL DEFAULT '#A6CC33',
	right_leg_color TEXT NOT NULL DEFAULT '#A6CC33',
	equipped_items JSONB NOT NULL DEFAULT '[]'::jsonb,
	body_type TEXT NOT NULL DEFAULT 'R6'
		CHECK (body_type IN ('R6', 'R15')),
	created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.avatar_outfits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Avatar outfits are viewable by everyone"
	ON public.avatar_outfits FOR SELECT
	USING (true);

CREATE POLICY "Users can insert their own avatar outfit"
	ON public.avatar_outfits FOR INSERT
	WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own avatar outfit"
	ON public.avatar_outfits FOR UPDATE
	USING (auth.uid() = user_id)
	WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own avatar outfit"
	ON public.avatar_outfits FOR DELETE
	USING (auth.uid() = user_id);

CREATE TRIGGER avatar_outfits_touch_updated_at
BEFORE UPDATE ON public.avatar_outfits
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

-- ============================================================================
-- STEP 7: SOCIAL GRAPH
-- ============================================================================

CREATE TABLE public.friendships (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	user1 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	user2 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	status TEXT NOT NULL DEFAULT 'accepted'
		CHECK (status IN ('accepted')),
	created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	CHECK (user1 <> user2),
	CHECK (user1 < user2),
	UNIQUE (user1, user2)
);

CREATE INDEX idx_friendships_user1 ON public.friendships(user1);
CREATE INDEX idx_friendships_user2 ON public.friendships(user2);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own friendships"
	ON public.friendships FOR SELECT
	USING (auth.uid() = user1 OR auth.uid() = user2);

CREATE POLICY "Users can create friendships they belong to"
	ON public.friendships FOR INSERT
	WITH CHECK (auth.uid() = user1 OR auth.uid() = user2);

CREATE POLICY "Users can delete friendships they belong to"
	ON public.friendships FOR DELETE
	USING (auth.uid() = user1 OR auth.uid() = user2);

CREATE TRIGGER friendships_touch_updated_at
BEFORE UPDATE ON public.friendships
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE public.friend_requests (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	from_user UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	to_user UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	status TEXT NOT NULL DEFAULT 'pending'
		CHECK (status IN ('pending')),
	created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	CHECK (from_user <> to_user),
	UNIQUE (from_user, to_user)
);

CREATE INDEX idx_friend_requests_from_user ON public.friend_requests(from_user);
CREATE INDEX idx_friend_requests_to_user ON public.friend_requests(to_user);

ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own friend requests"
	ON public.friend_requests FOR SELECT
	USING (auth.uid() = from_user OR auth.uid() = to_user);

CREATE POLICY "Users can send friend requests"
	ON public.friend_requests FOR INSERT
	WITH CHECK (auth.uid() = from_user);

CREATE POLICY "Users can delete their own friend requests"
	ON public.friend_requests FOR DELETE
	USING (auth.uid() = from_user OR auth.uid() = to_user);

CREATE TRIGGER friend_requests_touch_updated_at
BEFORE UPDATE ON public.friend_requests
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

-- ============================================================================
-- STEP 8: AUTH USER BOOTSTRAP TRIGGER
-- ============================================================================

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- STEP 9: SEED THE CATALOG
-- ============================================================================

INSERT INTO public.catalog_items (name, category, type, description, price_robux, price_tickets)
VALUES
	('Pal Hair', 'Accessories', 'hair', 'A classic starter hairstyle.', 0, 0),
	('Brown Hair', 'Accessories', 'hair', 'Simple hair for everyday avatars.', 10, 0),
	('Smile', 'Faces', 'face', 'The classic smile.', 0, 0),
	('Winning Smile', 'Faces', 'face', 'You are winning.', 50, 0),
	('Classic Red Tee', 'Shirts', 'shirt', 'A clean classic shirt.', 5, 0),
	('Dark Green Jeans', 'Pants', 'pants', 'A grounded default pants item.', 5, 0),
	('Linked Sword', 'Gear', 'gear', 'The original sword.', 100, 0)
ON CONFLICT DO NOTHING;

COMMIT;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- SELECT count(*) FROM auth.users;
-- SELECT count(*) FROM public.profiles;
-- SELECT count(*) FROM public.maps;
-- SELECT count(*) FROM public.active_servers;
-- SELECT count(*) FROM public.friendships;
-- SELECT count(*) FROM public.friend_requests;
