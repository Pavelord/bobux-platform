-- Safe live migration: grants for maps Data API access and owner-name cleanup.
-- This does not wipe data.

grant select on public.maps to anon;
grant select, insert, update, delete on public.maps to authenticated;

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
