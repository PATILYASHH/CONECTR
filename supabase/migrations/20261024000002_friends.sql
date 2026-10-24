-- Phase 2: friends.
--
-- Paste into Supabase dashboard → SQL Editor → Run, once, after the phase 1
-- migration. Re-running fails on "already exists" instead of silently
-- changing anything.
--
-- Design: docs/superpowers/specs/2026-10-24-friends-shared-dues-design.md

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  -- Named so the app's PostgREST embeds can pick each side explicitly.
  requester_id uuid not null
    constraint friendships_requester_id_fkey
    references public.profiles (id) on delete cascade,
  addressee_id uuid not null
    constraint friendships_addressee_id_fkey
    references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    constraint friendship_status
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint friendship_not_self check (requester_id <> addressee_id)
);

-- One row per pair, whichever way round the request went.
create unique index friendships_pair on public.friendships (  
  least(requester_id, addressee_id),
  greatest(requester_id, addressee_id)
);
create index friendships_requester on public.friendships (requester_id);
create index friendships_addressee on public.friendships (addressee_id);

alter table public.friendships enable row level security;

-- Reads and deletes go straight to the table; creating and answering
-- requests only through the functions below, which hold the rules.
revoke all on public.friendships from anon, authenticated;
grant select, delete on public.friendships to authenticated;

create policy "Users see their own friendships"
  on public.friendships for select to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

-- Cancelling a sent request and unfriending are both just deleting the
-- row. Phase 3's shared entries cascade from it.
create policy "Either side can end a friendship"
  on public.friendships for delete to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

-- Widens phase 1's "yourself only": a request has to show who it's from
-- (and to), so both sides of any friendship row can read each other's
-- username and display name. Nothing else is in a profile.
create policy "Users read profiles they have a friendship with"
  on public.profiles for select to authenticated
  using (exists (
    select 1 from public.friendships f
    where (f.requester_id = (select auth.uid()) and f.addressee_id = profiles.id)
       or (f.addressee_id = (select auth.uid()) and f.requester_id = profiles.id)
  ));

-- Exact username → that one person. security definer so it can look past
-- profiles' RLS, but it never lists or prefix-matches anyone: you have to
-- already know the name.
create function public.find_user(p_username text)
returns table (id uuid, username text, display_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name
  from public.profiles p
  where p.username = lower(p_username);
$$;

-- Sends a request, or accepts theirs if they already asked you (even one
-- you declined before — asking back is a yes). Already friends, or already
-- asked: returns the existing row unchanged.
create function public.send_friend_request(p_addressee_id uuid)
returns public.friendships
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_row public.friendships;
begin
  if v_me is null then
    raise exception 'not_signed_in';
  end if;
  if p_addressee_id = v_me then
    raise exception 'cannot_friend_self';
  end if;

  select * into v_row
  from public.friendships f
  where least(f.requester_id, f.addressee_id) = least(v_me, p_addressee_id)
    and greatest(f.requester_id, f.addressee_id) = greatest(v_me, p_addressee_id)
  for update;

  if not found then
    insert into public.friendships (requester_id, addressee_id)
    values (v_me, p_addressee_id)
    returning * into v_row;
  elsif v_row.addressee_id = v_me and v_row.status <> 'accepted' then
    update public.friendships
    set status = 'accepted', responded_at = now()
    where id = v_row.id
    returning * into v_row;
  end if;

  return v_row;
end;
$$;

-- Only the person asked can answer, and only while it's still pending.
-- A declined request stays (as 'declined') so it can't simply be re-sent;
-- the app keeps showing it to the sender as "Requested".
create function public.respond_friend_request(
  p_friendship_id uuid,
  p_accept boolean
)
returns public.friendships
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.friendships;
begin
  update public.friendships
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = p_friendship_id
    and addressee_id = (select auth.uid())
    and status = 'pending'
  returning * into v_row;

  if not found then
    -- Cancelled by the sender meanwhile, or not yours to answer.
    raise exception 'request_not_found';
  end if;

  return v_row;
end;
$$;

revoke execute on function public.find_user(text) from public, anon;
revoke execute on function public.send_friend_request(uuid) from public, anon;
revoke execute on function public.respond_friend_request(uuid, boolean) from public, anon;
grant execute on function public.find_user(text) to authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;

-- Live updates. Inserts and updates reach only the two people in the row
-- (RLS); deletes reach every subscriber but carry only the row id, so the
-- app treats any event as "re-read your list".
alter publication supabase_realtime add table public.friendships;
