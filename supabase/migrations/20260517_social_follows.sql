-- Adds Roblox-style one-way follow relationships without changing friendships.
-- Safe for existing databases: no data is dropped.

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
