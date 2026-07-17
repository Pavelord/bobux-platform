-- Keep map deletion atomic with its Storage-backed audio assets.
-- This is intentionally idempotent so it can be re-run safely on live projects.

create or replace function public.delete_own_map_and_cleanup(target_map_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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

    select owner_id, data
    into map_owner_id, map_payload
    from public.maps
    where id = clean_map_id;

    if map_owner_id is null then
        return jsonb_build_object(
            'ok', true,
            'map_id', clean_map_id,
            'deleted_maps', 0,
            'deleted_active_servers', 0,
            'deleted_assets', 0,
            'note', 'map_not_found'
        );
    end if;

    if map_owner_id <> current_user_id then
        raise exception 'only the owner can delete this map';
    end if;

    for asset_url in
        select value
        from jsonb_each_text(coalesce(map_payload->'mode_asset_urls', '{}'::jsonb))
    loop
        asset_object_name := split_part(asset_url, '/object/public/map-assets/', 2);
        if asset_object_name <> '' then
            delete from storage.objects
            where bucket_id = 'map-assets'
              and owner = current_user_id
              and name = asset_object_name;
            get diagnostics row_count_value = row_count;
            deleted_assets := deleted_assets + row_count_value;
        end if;
    end loop;

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
        'deleted_active_servers', deleted_servers,
        'deleted_assets', deleted_assets
    );
end;
$$;

create or replace function public.delete_own_maps_by_name_and_cleanup(target_map_name text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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
        select id, data
        from public.maps
        where owner_id = current_user_id
          and name = clean_map_name
    loop
        for asset_url in
            select value
            from jsonb_each_text(coalesce(map_record.data->'mode_asset_urls', '{}'::jsonb))
        loop
            asset_object_name := split_part(asset_url, '/object/public/map-assets/', 2);
            if asset_object_name <> '' then
                delete from storage.objects
                where bucket_id = 'map-assets'
                  and owner = current_user_id
                  and name = asset_object_name;
                get diagnostics row_count_value = row_count;
                deleted_assets := deleted_assets + row_count_value;
            end if;
        end loop;

        delete from public.active_servers where map_id = map_record.id;
        get diagnostics row_count_value = row_count;
        deleted_servers := deleted_servers + row_count_value;
    end loop;

    delete from public.maps
    where owner_id = current_user_id
      and name = clean_map_name;
    get diagnostics deleted_maps = row_count;

    return jsonb_build_object(
        'ok', true,
        'map_name', clean_map_name,
        'deleted_maps', deleted_maps,
        'deleted_active_servers', deleted_servers,
        'deleted_assets', deleted_assets
    );
end;
$$;

revoke execute on function public.delete_own_map_and_cleanup(text) from public;
revoke execute on function public.delete_own_map_and_cleanup(text) from anon;
revoke execute on function public.delete_own_maps_by_name_and_cleanup(text) from public;
revoke execute on function public.delete_own_maps_by_name_and_cleanup(text) from anon;
grant execute on function public.delete_own_map_and_cleanup(text) to authenticated;
grant execute on function public.delete_own_maps_by_name_and_cleanup(text) to authenticated;
