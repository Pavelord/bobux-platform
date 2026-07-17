alter table public.active_servers
add column if not exists member_user_ids text[] not null default '{}';

update public.active_servers
set member_user_ids = case
	when host_user_id is null or btrim(host_user_id) = '' then '{}'::text[]
	else array[host_user_id]
end
where member_user_ids is null or cardinality(member_user_ids) = 0;

create index if not exists idx_active_servers_member_user_ids
on public.active_servers
using gin (member_user_ids);
