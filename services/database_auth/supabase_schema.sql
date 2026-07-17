create table if not exists profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    username text not null unique,
    status text not null default 'offline',
    current_game text not null default '',
    current_server_host text not null default '',
    current_server_ip text not null default '',
    current_server_port integer not null default 0,
    updated_at timestamptz not null default now()
);

create table if not exists maps (
    id text primary key,
    owner_id uuid not null references profiles(id) on delete cascade,
    name text not null,
    description text not null default '',
    data jsonb not null,
    thumbnail text not null default '',
    cloud_version_id text not null default '',
    owner_name text not null default '',
    updated_at timestamptz not null default now()
);

create table if not exists friendships (
    user1 uuid not null references profiles(id) on delete cascade,
    user2 uuid not null references profiles(id) on delete cascade,
    status text not null default 'accepted',
    created_at timestamptz not null default now(),
    primary key (user1, user2),
    check (user1 <> user2)
);

create table if not exists friend_requests (
    from_user uuid not null references profiles(id) on delete cascade,
    to_user uuid not null references profiles(id) on delete cascade,
    status text not null default 'pending',
    created_at timestamptz not null default now(),
    primary key (from_user, to_user),
    check (from_user <> to_user)
);

create table if not exists active_servers (
    server_key text primary key,
    room_id text not null default '',
    player_id text not null default '',
    is_host boolean not null default false,
    transport text not null default 'websocket',
    server_url text not null default '',
    ip text not null default '',
    port integer not null default 0,
    map_id text not null default '',
    map_name text not null default '',
    cloud_version_id text not null default '',
    host_user_id uuid not null references profiles(id) on delete cascade,
    host_username text not null default '',
    players_count integer not null default 0,
    max_players integer not null default 10,
    status text not null default 'active',
    last_seen bigint not null default 0,
    started_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    check (transport in ('websocket'))
);

create index if not exists idx_profiles_username on profiles(username);
create index if not exists idx_profiles_status on profiles(status);
create index if not exists idx_maps_owner_id on maps(owner_id);
create index if not exists idx_maps_updated_at on maps(updated_at desc);
create index if not exists idx_friendships_user1 on friendships(user1);
create index if not exists idx_friendships_user2 on friendships(user2);
create index if not exists idx_friend_requests_to_user on friend_requests(to_user, status);
create index if not exists idx_active_servers_map_id on active_servers(map_id);
create index if not exists idx_active_servers_status on active_servers(status, players_count desc);
create unique index if not exists idx_active_servers_room_player on active_servers(room_id, player_id);
create index if not exists idx_active_servers_room_created on active_servers(room_id, created_at asc);

alter table public.profiles enable row level security;
alter table public.maps enable row level security;
alter table public.friendships enable row level security;
alter table public.friend_requests enable row level security;
alter table public.active_servers enable row level security;

revoke all on table public.profiles from anon;
revoke all on table public.maps from anon;
revoke all on table public.friendships from anon;
revoke all on table public.friend_requests from anon;
revoke all on table public.active_servers from anon;

grant select, insert, update on table public.profiles to authenticated;
grant select, insert, update, delete on table public.maps to authenticated;
grant select, insert, update, delete on table public.friendships to authenticated;
grant select, insert, update, delete on table public.friend_requests to authenticated;
grant select, insert, update, delete on table public.active_servers to authenticated;

drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all"
on public.profiles for select
to authenticated
using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles for insert
to authenticated
with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists "maps_select_all" on public.maps;
create policy "maps_select_all"
on public.maps for select
to authenticated
using (true);

drop policy if exists "maps_insert_own" on public.maps;
create policy "maps_insert_own"
on public.maps for insert
to authenticated
with check (owner_id = auth.uid());

drop policy if exists "maps_update_own" on public.maps;
create policy "maps_update_own"
on public.maps for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "maps_delete_own" on public.maps;
create policy "maps_delete_own"
on public.maps for delete
to authenticated
using (owner_id = auth.uid());

drop policy if exists "friendships_select_participant" on public.friendships;
create policy "friendships_select_participant"
on public.friendships for select
to authenticated
using (user1 = auth.uid() or user2 = auth.uid());

drop policy if exists "friendships_insert_self" on public.friendships;
create policy "friendships_insert_self"
on public.friendships for insert
to authenticated
with check (user1 = auth.uid() or user2 = auth.uid());

drop policy if exists "friendships_update_participant" on public.friendships;
create policy "friendships_update_participant"
on public.friendships for update
to authenticated
using (user1 = auth.uid() or user2 = auth.uid())
with check (user1 = auth.uid() or user2 = auth.uid());

drop policy if exists "friendships_delete_participant" on public.friendships;
create policy "friendships_delete_participant"
on public.friendships for delete
to authenticated
using (user1 = auth.uid() or user2 = auth.uid());

drop policy if exists "friend_requests_select_participant" on public.friend_requests;
create policy "friend_requests_select_participant"
on public.friend_requests for select
to authenticated
using (from_user = auth.uid() or to_user = auth.uid());

drop policy if exists "friend_requests_insert_own" on public.friend_requests;
create policy "friend_requests_insert_own"
on public.friend_requests for insert
to authenticated
with check (from_user = auth.uid());

drop policy if exists "friend_requests_update_participant" on public.friend_requests;
create policy "friend_requests_update_participant"
on public.friend_requests for update
to authenticated
using (from_user = auth.uid() or to_user = auth.uid())
with check (from_user = auth.uid() or to_user = auth.uid());

drop policy if exists "friend_requests_delete_participant" on public.friend_requests;
create policy "friend_requests_delete_participant"
on public.friend_requests for delete
to authenticated
using (from_user = auth.uid() or to_user = auth.uid());

drop policy if exists "active_servers_select_all" on public.active_servers;
create policy "active_servers_select_all"
on public.active_servers for select
to authenticated
using (true);

drop policy if exists "active_servers_insert_own" on public.active_servers;
create policy "active_servers_insert_own"
on public.active_servers for insert
to authenticated
with check (host_user_id = auth.uid());

drop policy if exists "active_servers_update_own" on public.active_servers;
create policy "active_servers_update_own"
on public.active_servers for update
to authenticated
using (host_user_id = auth.uid())
with check (host_user_id = auth.uid());

drop policy if exists "active_servers_delete_own" on public.active_servers;
create policy "active_servers_delete_own"
on public.active_servers for delete
to authenticated
using (host_user_id = auth.uid());
