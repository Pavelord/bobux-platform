-- Safe live migration: atomic map delete for the authenticated owner.
-- This does not wipe data. It only adds RPC helpers used by the game client.

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
