-- Phase 1: usernames.
--
-- Paste into Supabase dashboard → SQL Editor → Run, once. Re-running fails
-- on "already exists" instead of silently changing anything.
--
-- Design: docs/superpowers/specs/2026-10-24-friends-shared-dues-design.md

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  -- Stored lowercase (the app lowercases before sending, and the check
  -- rejects anything else), so the plain unique constraint is already
  -- case-insensitive: "Yash" and "yash" can't both exist.
  username text not null unique
    constraint username_format check (username ~ '^[a-z0-9_]{3,20}$'),
  -- Unused until friends lists (phase 2); here now so that phase doesn't
  -- need to alter a table people are already writing to.
  display_name text
    constraint display_name_length check (char_length(display_name) between 1 and 50),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Nothing for signed-out clients, and only the columns a user may set.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant insert (id, username, display_name) on public.profiles to authenticated;
grant update (username, display_name) on public.profiles to authenticated;

-- Phase 2 widens reads to accepted friends. Until then: yourself only.
create policy "Users read their own profile"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "Users create their own profile"
  on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));

create policy "Users update their own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Availability check for the pick-username screen. security definer so it
-- can see every username without RLS exposing a single profile row — it
-- only ever answers yes/no for one exact name.
create function public.username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.profiles where username = lower(p_username)
  );
$$;

revoke execute on function public.username_available(text) from public, anon;
grant execute on function public.username_available(text) to authenticated;
