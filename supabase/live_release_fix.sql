-- Bobux live release fixes.
-- Safe for an existing production/dev database: this file does NOT drop tables
-- and does NOT delete users or maps.

-- 1) Map visibility and ownership. Published maps are public, but only the
-- authenticated owner can create/update/delete their own maps.
alter table public.maps enable row level security;

drop policy if exists "Published maps are viewable by everyone" on public.maps;
drop policy if exists "Users can insert their own maps" on public.maps;
drop policy if exists "Users can update their own maps" on public.maps;
drop policy if exists "Users can delete their own maps" on public.maps;

create policy "Published maps are viewable by everyone"
	on public.maps
	for select
	to anon, authenticated
	using (is_published = true or auth.uid() = owner_id);

create policy "Users can insert their own maps"
	on public.maps
	for insert
	to authenticated
	with check (auth.uid() = owner_id);

create policy "Users can update their own maps"
	on public.maps
	for update
	to authenticated
	using (auth.uid() = owner_id)
	with check (auth.uid() = owner_id);

create policy "Users can delete their own maps"
	on public.maps
	for delete
	to authenticated
	using (auth.uid() = owner_id);

grant select on public.maps to anon;
grant select, insert, update, delete on public.maps to authenticated;

-- 2) Public friend counts for profile pages without exposing private friend
-- row details through broad SELECT policies.
create or replace function public.get_friend_count(target_user uuid)
returns integer
language sql
security definer
set search_path = public
as $$
	select count(*)::integer
	from public.friendships
	where status = 'accepted'
		and (user1 = target_user or user2 = target_user);
$$;

grant execute on function public.get_friend_count(uuid) to authenticated;

-- 3) Roblox-style follow graph. This is separate from friendships:
-- following someone does not require accepting a friend request.
create table if not exists public.follows (
	id uuid primary key default gen_random_uuid(),
	follower_id uuid not null references auth.users(id) on delete cascade,
	following_id uuid not null references auth.users(id) on delete cascade,
	created_at timestamptz not null default timezone('utc', now()),
	updated_at timestamptz not null default timezone('utc', now()),
	check (follower_id <> following_id),
	unique (follower_id, following_id)
);

create index if not exists idx_follows_follower_id on public.follows(follower_id);
create index if not exists idx_follows_following_id on public.follows(following_id);

alter table public.follows enable row level security;

drop policy if exists "Follow rows are visible to signed in users" on public.follows;
drop policy if exists "Users can follow from their own account" on public.follows;
drop policy if exists "Users can unfollow from their own account" on public.follows;

create policy "Follow rows are visible to signed in users"
	on public.follows
	for select
	to authenticated
	using (true);

create policy "Users can follow from their own account"
	on public.follows
	for insert
	to authenticated
	with check (auth.uid() = follower_id);

create policy "Users can unfollow from their own account"
	on public.follows
	for delete
	to authenticated
	using (auth.uid() = follower_id);

drop trigger if exists follows_touch_updated_at on public.follows;
create trigger follows_touch_updated_at
before update on public.follows
for each row
execute function public.touch_updated_at();

grant select, insert, delete on public.follows to authenticated;
grant usage, select on all sequences in schema public to authenticated;

create or replace function public.get_follow_counts(target_user uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
	select jsonb_build_object(
		'followers_count', (
			select count(*)::integer
			from public.follows
			where following_id = target_user
		),
		'following_count', (
			select count(*)::integer
			from public.follows
			where follower_id = target_user
		)
	);
$$;

grant execute on function public.get_follow_counts(uuid) to authenticated;

-- 4) Optional maintenance helper: remove orphaned active server rows for maps
-- that are no longer published. Run manually if old ghosts are visible after
-- a schema/policy repair.
create or replace function public.cleanup_unpublished_active_servers()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
	deleted_count integer;
begin
	delete from public.active_servers s
	where s.map_id is not null
		and s.map_id <> ''
		and not exists (
			select 1
			from public.maps m
			where m.id = s.map_id and m.is_published = true
		);
	get diagnostics deleted_count = row_count;
	return deleted_count;
end;
$$;

grant execute on function public.cleanup_unpublished_active_servers() to authenticated;

-- 5) Atomic owner-only map delete. The game client calls this RPC when a
-- player deletes an experience from Develop. It removes the map row and any
-- active server ghosts for that map in one transaction, while still checking
-- auth.uid() against maps.owner_id.
create or replace function public.delete_own_map_and_cleanup(target_map_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
	clean_map_id text := btrim(coalesce(target_map_id, ''));
	current_user_id uuid := auth.uid();
	map_owner_id uuid;
	deleted_servers integer := 0;
	deleted_maps integer := 0;
begin
	if clean_map_id = '' then
		raise exception 'target_map_id is empty';
	end if;
	if current_user_id is null then
		raise exception 'authenticated user is required';
	end if;

	select owner_id
	into map_owner_id
	from public.maps
	where id = clean_map_id;

	if map_owner_id is null then
		return jsonb_build_object(
			'ok', true,
			'map_id', clean_map_id,
			'deleted_maps', 0,
			'deleted_active_servers', 0,
			'note', 'map_not_found'
		);
	end if;

	if map_owner_id <> current_user_id then
		raise exception 'only the owner can delete this map';
	end if;

	delete from public.active_servers
	where map_id = clean_map_id;
	get diagnostics deleted_servers = row_count;

	delete from public.maps
	where id = clean_map_id
		and owner_id = current_user_id;
	get diagnostics deleted_maps = row_count;

	return jsonb_build_object(
		'ok', true,
		'map_id', clean_map_id,
		'deleted_maps', deleted_maps,
		'deleted_active_servers', deleted_servers
	);
end;
$$;

grant execute on function public.delete_own_map_and_cleanup(text) to authenticated;

-- 6) Cleanup older duplicate/ghost map rows by owner + visible name. This is
-- used only after the authenticated owner deletes an experience from Develop.
create or replace function public.delete_own_maps_by_name_and_cleanup(target_map_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
	clean_map_name text := btrim(coalesce(target_map_name, ''));
	current_user_id uuid := auth.uid();
	deleted_servers integer := 0;
	deleted_maps integer := 0;
begin
	if clean_map_name = '' then
		raise exception 'target_map_name is empty';
	end if;
	if current_user_id is null then
		raise exception 'authenticated user is required';
	end if;

	delete from public.active_servers s
	where exists (
		select 1
		from public.maps m
		where m.id = s.map_id
			and m.owner_id = current_user_id
			and lower(btrim(m.name)) = lower(clean_map_name)
	);
	get diagnostics deleted_servers = row_count;

	delete from public.maps
	where owner_id = current_user_id
		and lower(btrim(name)) = lower(clean_map_name);
	get diagnostics deleted_maps = row_count;

	return jsonb_build_object(
		'ok', true,
		'name', clean_map_name,
		'deleted_maps', deleted_maps,
		'deleted_active_servers', deleted_servers
	);
end;
$$;

grant execute on function public.delete_own_maps_by_name_and_cleanup(text) to authenticated;

-- 7) Storage bucket for map audio/asset files. Large music playlists must not
-- be embedded into maps.data JSON, otherwise Godot/Supabase can fail with
-- HTTP transport result 4/status 0. The client uploads files to:
-- map-assets/{auth.uid()}/{map_id}/{asset_file}
insert into storage.buckets (id, name, public, file_size_limit)
values ('map-assets', 'map-assets', true, 52428800)
on conflict (id) do update
set
	public = excluded.public,
	file_size_limit = excluded.file_size_limit;

do $$
begin
	execute 'drop policy if exists "Map asset public read" on storage.objects';

	if not exists (
		select 1 from pg_policies
		where schemaname = 'storage'
			and tablename = 'objects'
			and policyname = 'Users can read their own map assets'
	) then
		execute 'create policy "Users can read their own map assets"
			on storage.objects
			for select
			to authenticated
			using (
				bucket_id = ''map-assets''
				and (storage.foldername(name))[1] = auth.uid()::text
			)';
	end if;

	if not exists (
		select 1 from pg_policies
		where schemaname = 'storage'
			and tablename = 'objects'
			and policyname = 'Users can upload their own map assets'
	) then
		execute 'create policy "Users can upload their own map assets"
			on storage.objects
			for insert
			to authenticated
			with check (
				bucket_id = ''map-assets''
				and (storage.foldername(name))[1] = auth.uid()::text
			)';
	end if;

	if not exists (
		select 1 from pg_policies
		where schemaname = 'storage'
			and tablename = 'objects'
			and policyname = 'Users can update their own map assets'
	) then
		execute 'create policy "Users can update their own map assets"
			on storage.objects
			for update
			to authenticated
			using (
				bucket_id = ''map-assets''
				and (storage.foldername(name))[1] = auth.uid()::text
			)
			with check (
				bucket_id = ''map-assets''
				and (storage.foldername(name))[1] = auth.uid()::text
			)';
	end if;

	if not exists (
		select 1 from pg_policies
		where schemaname = 'storage'
			and tablename = 'objects'
			and policyname = 'Users can delete their own map assets'
	) then
		execute 'create policy "Users can delete their own map assets"
			on storage.objects
			for delete
			to authenticated
			using (
				bucket_id = ''map-assets''
				and (storage.foldername(name))[1] = auth.uid()::text
			)';
	end if;
end $$;

-- 8) Release hardening: map deletion also removes Storage-backed map assets.
-- Keep this at the end so older live deployments get the newest cleanup RPC.
create or replace function public.delete_own_map_and_cleanup(target_map_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
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
begin
	if clean_map_id = '' then
		raise exception 'target_map_id is empty';
	end if;
	if current_user_id is null then
		raise exception 'authenticated user is required';
	end if;

	select owner_id, data into map_owner_id, map_payload
	from public.maps
	where id = clean_map_id;

	if map_owner_id is null then
		return jsonb_build_object('ok', true, 'map_id', clean_map_id, 'deleted_maps', 0, 'deleted_active_servers', 0, 'deleted_assets', 0, 'note', 'map_not_found');
	end if;
	if map_owner_id <> current_user_id then
		raise exception 'only the owner can delete this map';
	end if;

	for asset_url in select value from jsonb_each_text(coalesce(map_payload->'mode_asset_urls', '{}'::jsonb)) loop
		asset_object_name := split_part(asset_url, '/object/public/map-assets/', 2);
		if asset_object_name <> '' then
			delete from storage.objects
			where bucket_id = 'map-assets' and owner = current_user_id and name = asset_object_name;
			get diagnostics row_count_value = row_count;
			deleted_assets := deleted_assets + row_count_value;
		end if;
	end loop;

	delete from public.active_servers where map_id = clean_map_id;
	get diagnostics deleted_servers = row_count;
	delete from public.maps where id = clean_map_id and owner_id = current_user_id;
	get diagnostics deleted_maps = row_count;

	return jsonb_build_object('ok', true, 'map_id', clean_map_id, 'deleted_maps', deleted_maps, 'deleted_active_servers', deleted_servers, 'deleted_assets', deleted_assets);
end;
$$;

create or replace function public.delete_own_maps_by_name_and_cleanup(target_map_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
	clean_map_name text := btrim(coalesce(target_map_name, ''));
	current_user_id uuid := auth.uid();
	map_record record;
	asset_url text;
	asset_object_name text;
	deleted_servers integer := 0;
	deleted_assets integer := 0;
	deleted_maps integer := 0;
	row_count_value integer := 0;
begin
	if clean_map_name = '' then
		raise exception 'target_map_name is empty';
	end if;
	if current_user_id is null then
		raise exception 'authenticated user is required';
	end if;

	for map_record in
		select id, data from public.maps
		where owner_id = current_user_id and name = clean_map_name
	loop
		for asset_url in select value from jsonb_each_text(coalesce(map_record.data->'mode_asset_urls', '{}'::jsonb)) loop
			asset_object_name := split_part(asset_url, '/object/public/map-assets/', 2);
			if asset_object_name <> '' then
				delete from storage.objects
				where bucket_id = 'map-assets' and owner = current_user_id and name = asset_object_name;
				get diagnostics row_count_value = row_count;
				deleted_assets := deleted_assets + row_count_value;
			end if;
		end loop;
		delete from public.active_servers where map_id = map_record.id;
		get diagnostics row_count_value = row_count;
		deleted_servers := deleted_servers + row_count_value;
	end loop;

	delete from public.maps where owner_id = current_user_id and name = clean_map_name;
	get diagnostics deleted_maps = row_count;

	return jsonb_build_object('ok', true, 'map_name', clean_map_name, 'deleted_maps', deleted_maps, 'deleted_active_servers', deleted_servers, 'deleted_assets', deleted_assets);
end;
$$;

revoke execute on function public.delete_own_map_and_cleanup(text) from public;
revoke execute on function public.delete_own_map_and_cleanup(text) from anon;
revoke execute on function public.delete_own_maps_by_name_and_cleanup(text) from public;
revoke execute on function public.delete_own_maps_by_name_and_cleanup(text) from anon;
grant execute on function public.delete_own_map_and_cleanup(text) to authenticated;
grant execute on function public.delete_own_maps_by_name_and_cleanup(text) to authenticated;
