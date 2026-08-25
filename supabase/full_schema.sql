-- ============================================================================
-- FULL SUPABASE SQL SCHEMA -- Dedicated Authoritative WebSocket Stack
-- Canonical bootstrap schema for a fresh database or an intentional full reset.
-- Do NOT use this as an in-place production migration for a live database whose
-- current rows you want to preserve.
-- This script intentionally resets the multiplayer-facing data model so the
-- project starts from a clean slate with no legacy transport leftovers.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- STEP 0: REMOVE LEGACY OBJECTS AND DATA (DESTRUCTIVE RESET)
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user_profile() CASCADE;
DROP FUNCTION IF EXISTS public.touch_updated_at() CASCADE;
DROP FUNCTION IF EXISTS public.cleanup_stale_active_servers() CASCADE;

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
DROP TABLE IF EXISTS public.follows CASCADE;
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.avatar_outfits CASCADE;
DROP TABLE IF EXISTS public.catalog_items CASCADE;
DROP TABLE IF EXISTS public.active_servers CASCADE;
DROP TABLE IF EXISTS public.maps CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- Hard reset auth users too so a clean-room local/dev bootstrap has no stale
-- accounts left behind. Keep this destructive line only for intentional resets.
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

GRANT SELECT ON public.maps TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.maps TO authenticated;

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
	member_user_ids TEXT[] NOT NULL DEFAULT '{}',
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
CREATE INDEX idx_active_servers_member_user_ids ON public.active_servers USING GIN (member_user_ids);

ALTER TABLE public.active_servers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active servers are viewable by everyone"
	ON public.active_servers FOR SELECT
	USING (true);

CREATE POLICY "Authenticated users can insert active servers"
	ON public.active_servers FOR INSERT
	TO authenticated
	WITH CHECK (true);

CREATE POLICY "Users can update their own active servers"
	ON public.active_servers FOR UPDATE
	TO authenticated
	USING (host_user_id = auth.uid()::text)
	WITH CHECK (host_user_id = auth.uid()::text);

CREATE POLICY "Users can delete their own active servers"
	ON public.active_servers FOR DELETE
	TO authenticated
	USING (host_user_id = auth.uid()::text);

CREATE POLICY "Service role has full access to active servers"
	ON public.active_servers FOR ALL
	TO service_role
	USING (true)
	WITH CHECK (true);

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

CREATE TABLE public.follows (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	following_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
	CHECK (follower_id <> following_id),
	UNIQUE (follower_id, following_id)
);

CREATE INDEX idx_follows_follower_id ON public.follows(follower_id);
CREATE INDEX idx_follows_following_id ON public.follows(following_id);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Follow rows are visible to signed in users"
	ON public.follows FOR SELECT
	TO authenticated
	USING (true);

CREATE POLICY "Users can follow from their own account"
	ON public.follows FOR INSERT
	TO authenticated
	WITH CHECK (auth.uid() = follower_id);

CREATE POLICY "Users can unfollow from their own account"
	ON public.follows FOR DELETE
	TO authenticated
	USING (auth.uid() = follower_id);

CREATE TRIGGER follows_touch_updated_at
BEFORE UPDATE ON public.follows
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();

GRANT SELECT, INSERT, DELETE ON public.follows TO authenticated;

-- ============================================================================
-- STEP 7B: SAFE MAINTENANCE RPC HELPERS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_friend_count(target_user uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
	SELECT count(*)::integer
	FROM public.friendships
	WHERE status = 'accepted'
		AND (user1 = target_user OR user2 = target_user);
$$;

GRANT EXECUTE ON FUNCTION public.get_friend_count(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_follow_counts(target_user uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
	SELECT jsonb_build_object(
		'followers_count', (
			SELECT count(*)::integer
			FROM public.follows
			WHERE following_id = target_user
		),
		'following_count', (
			SELECT count(*)::integer
			FROM public.follows
			WHERE follower_id = target_user
		)
	);
$$;

GRANT EXECUTE ON FUNCTION public.get_follow_counts(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_own_map_and_cleanup(target_map_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	clean_map_id text := btrim(coalesce(target_map_id, ''));
	current_user_id uuid := auth.uid();
	map_owner_id uuid;
	deleted_servers integer := 0;
	deleted_maps integer := 0;
BEGIN
	IF clean_map_id = '' THEN
		RAISE EXCEPTION 'target_map_id is empty';
	END IF;
	IF current_user_id IS NULL THEN
		RAISE EXCEPTION 'authenticated user is required';
	END IF;

	SELECT owner_id
	INTO map_owner_id
	FROM public.maps
	WHERE id = clean_map_id;

	IF map_owner_id IS NULL THEN
		RETURN jsonb_build_object(
			'ok', true,
			'map_id', clean_map_id,
			'deleted_maps', 0,
			'deleted_active_servers', 0,
			'note', 'map_not_found'
		);
	END IF;

	IF map_owner_id <> current_user_id THEN
		RAISE EXCEPTION 'only the owner can delete this map';
	END IF;

	DELETE FROM public.active_servers
	WHERE map_id = clean_map_id;
	GET DIAGNOSTICS deleted_servers = ROW_COUNT;

	DELETE FROM public.maps
	WHERE id = clean_map_id
		AND owner_id = current_user_id;
	GET DIAGNOSTICS deleted_maps = ROW_COUNT;

	RETURN jsonb_build_object(
		'ok', true,
		'map_id', clean_map_id,
		'deleted_maps', deleted_maps,
		'deleted_active_servers', deleted_servers
	);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_own_map_and_cleanup(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_own_maps_by_name_and_cleanup(target_map_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	clean_map_name text := btrim(coalesce(target_map_name, ''));
	current_user_id uuid := auth.uid();
	deleted_servers integer := 0;
	deleted_maps integer := 0;
BEGIN
	IF clean_map_name = '' THEN
		RAISE EXCEPTION 'target_map_name is empty';
	END IF;
	IF current_user_id IS NULL THEN
		RAISE EXCEPTION 'authenticated user is required';
	END IF;

	DELETE FROM public.active_servers s
	WHERE EXISTS (
		SELECT 1
		FROM public.maps m
		WHERE m.id = s.map_id
			AND m.owner_id = current_user_id
			AND lower(btrim(m.name)) = lower(clean_map_name)
	);
	GET DIAGNOSTICS deleted_servers = ROW_COUNT;

	DELETE FROM public.maps
	WHERE owner_id = current_user_id
		AND lower(btrim(name)) = lower(clean_map_name);
	GET DIAGNOSTICS deleted_maps = ROW_COUNT;

	RETURN jsonb_build_object(
		'ok', true,
		'name', clean_map_name,
		'deleted_maps', deleted_maps,
		'deleted_active_servers', deleted_servers
	);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_own_maps_by_name_and_cleanup(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.cleanup_unpublished_active_servers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	deleted_count integer;
BEGIN
	DELETE FROM public.active_servers s
	WHERE s.map_id IS NOT NULL
		AND s.map_id <> ''
		AND NOT EXISTS (
			SELECT 1
			FROM public.maps m
			WHERE m.id = s.map_id AND m.is_published = true
		);
	GET DIAGNOSTICS deleted_count = ROW_COUNT;
	RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_unpublished_active_servers() TO authenticated;

-- ============================================================================
-- STEP 8: MAP ASSET STORAGE
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('map-assets', 'map-assets', true, 52428800)
ON CONFLICT (id) DO UPDATE
SET
	public = EXCLUDED.public,
	file_size_limit = EXCLUDED.file_size_limit;

DO $$
BEGIN
	EXECUTE 'DROP POLICY IF EXISTS "Map asset public read" ON storage.objects';

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'storage'
			AND tablename = 'objects'
			AND policyname = 'Users can read their own map assets'
	) THEN
		EXECUTE 'CREATE POLICY "Users can read their own map assets"
			ON storage.objects
			FOR SELECT
			TO authenticated
			USING (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)';
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'storage'
			AND tablename = 'objects'
			AND policyname = 'Users can upload their own map assets'
	) THEN
		EXECUTE 'CREATE POLICY "Users can upload their own map assets"
			ON storage.objects
			FOR INSERT
			TO authenticated
			WITH CHECK (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)';
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'storage'
			AND tablename = 'objects'
			AND policyname = 'Users can update their own map assets'
	) THEN
		EXECUTE 'CREATE POLICY "Users can update their own map assets"
			ON storage.objects
			FOR UPDATE
			TO authenticated
			USING (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)
			WITH CHECK (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)';
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'storage'
			AND tablename = 'objects'
			AND policyname = 'Users can delete their own map assets'
	) THEN
		EXECUTE 'CREATE POLICY "Users can delete their own map assets"
			ON storage.objects
			FOR DELETE
			TO authenticated
			USING (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)';
	END IF;
END $$;

-- ============================================================================
-- STEP 9: AUTH USER BOOTSTRAP TRIGGER
-- ============================================================================

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- STEP 10: SEED THE CATALOG
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

-- Release override: map deletion must also remove Storage-backed audio assets.
-- Kept after COMMIT as a standalone idempotent block for existing databases.
BEGIN;

CREATE OR REPLACE FUNCTION public.delete_own_map_and_cleanup(target_map_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	clean_map_id text := btrim(coalesce(target_map_id, ''));
	current_user_id uuid := auth.uid();
	map_owner_id uuid;
	map_payload jsonb := '{}'::jsonb;
	asset_url text;
	asset_object_name text;
	deleted_servers integer := 0;
	deleted_assets integer := 0;
	deleted_maps integer := 0;
	row_count_value integer := 0;
BEGIN
	IF clean_map_id = '' THEN
		RAISE EXCEPTION 'target_map_id is empty';
	END IF;
	IF current_user_id IS NULL THEN
		RAISE EXCEPTION 'authenticated user is required';
	END IF;

	SELECT owner_id, data INTO map_owner_id, map_payload
	FROM public.maps
	WHERE id = clean_map_id;

	IF map_owner_id IS NULL THEN
		RETURN jsonb_build_object('ok', true, 'map_id', clean_map_id, 'deleted_maps', 0, 'deleted_active_servers', 0, 'deleted_assets', 0, 'note', 'map_not_found');
	END IF;
	IF map_owner_id <> current_user_id THEN
		RAISE EXCEPTION 'only the owner can delete this map';
	END IF;

	FOR asset_url IN SELECT value FROM jsonb_each_text(coalesce(map_payload->'mode_asset_urls', '{}'::jsonb)) LOOP
		asset_object_name := split_part(asset_url, '/object/public/map-assets/', 2);
		IF asset_object_name <> '' THEN
			DELETE FROM storage.objects
			WHERE bucket_id = 'map-assets' AND owner = current_user_id AND name = asset_object_name;
			GET DIAGNOSTICS row_count_value = ROW_COUNT;
			deleted_assets := deleted_assets + row_count_value;
		END IF;
	END LOOP;

	DELETE FROM public.active_servers WHERE map_id = clean_map_id;
	GET DIAGNOSTICS deleted_servers = ROW_COUNT;
	DELETE FROM public.maps WHERE id = clean_map_id AND owner_id = current_user_id;
	GET DIAGNOSTICS deleted_maps = ROW_COUNT;

	RETURN jsonb_build_object('ok', true, 'map_id', clean_map_id, 'deleted_maps', deleted_maps, 'deleted_active_servers', deleted_servers, 'deleted_assets', deleted_assets);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_own_map_and_cleanup(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.delete_own_map_and_cleanup(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_own_map_and_cleanup(text) TO authenticated;

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
