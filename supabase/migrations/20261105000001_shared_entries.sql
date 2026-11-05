-- Phase 3: shared entries — a friend ↔ person ledger that is the same on
-- both sides.
--
-- Paste into Supabase dashboard → SQL Editor → Run, once, after the phase 2
-- migration. Re-running fails on "already exists" instead of silently
-- changing anything.
--
-- Design: docs/superpowers/specs/2026-10-24-friends-shared-dues-design.md
-- and its 2026-11-05 addendum.
--
-- One row is one entry between two friends: "owed_by owes owed_to this
-- much". Direction is stored absolutely; each side reads "they owe / I owe"
-- from its own id. The creator proposes it (pending); only the other side
-- accepts or rejects it. Accepted rows never change again — a mistake is
-- fixed with a correcting entry, like a bank statement.

create table public.shared_entries (
  id uuid primary key default gen_random_uuid(),
  friendship_id uuid not null
    constraint shared_entries_friendship_id_fkey
    references public.friendships (id) on delete cascade,
  created_by uuid not null
    references public.profiles (id) on delete cascade,
  -- The creating phone's own id for the entry, so a retried "add" (the
  -- answer lost on a bad network) finds the row it already made instead of
  -- making a second one. Edits and deletes name the entry by it too.
  client_ref text not null
    constraint shared_entry_client_ref_length
    check (char_length(client_ref) between 8 and 64),
  owed_by uuid not null references public.profiles (id) on delete cascade,
  owed_to uuid not null references public.profiles (id) on delete cascade,
  -- Minor units (paise, cents), as XPENC stores money.
  amount_minor bigint not null
    constraint shared_entry_amount check (amount_minor > 0),
  currency text not null
    constraint shared_entry_currency check (currency ~ '^[A-Z]{3}$'),
  entry_date date not null,
  due_date date,
  note text
    constraint shared_entry_note check (char_length(note) <= 500),
  -- "What we owe each other as of linking": the creator's existing balance
  -- with this person, so the history before linking stays private.
  is_opening boolean not null default false,
  status text not null default 'pending'
    constraint shared_entry_status
    check (status in ('pending', 'accepted', 'rejected')),
  -- Bumped on every change; an answer names the version it saw, so an
  -- entry edited meanwhile is never accepted unseen.
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint shared_entry_sides check (
    owed_by <> owed_to and created_by in (owed_by, owed_to)
  ),
  constraint shared_entry_client_ref_unique unique (created_by, client_ref)
);

create index shared_entries_friendship on public.shared_entries (friendship_id);
create index shared_entries_owed_by on public.shared_entries (owed_by);
create index shared_entries_owed_to on public.shared_entries (owed_to);

alter table public.shared_entries enable row level security;

-- Reads straight from the table; every write through the functions below.
revoke all on public.shared_entries from anon, authenticated;
grant select on public.shared_entries to authenticated;

-- The two people in an entry, and only while they're still friends.
create policy "Friends see the entries between them"
  on public.shared_entries for select to authenticated
  using (
    (select auth.uid()) in (owed_by, owed_to)
    and exists (
      select 1 from public.friendships f
      where f.id = shared_entries.friendship_id and f.status = 'accepted'
    )
  );

-- Belt and braces: nothing changes an accepted entry, whatever the caller.
create function public.shared_entries_lock_accepted()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'accepted' then
    raise exception 'entry_locked';
  end if;
  return new;
end;
$$;

create trigger shared_entries_lock_accepted
  before update on public.shared_entries
  for each row execute function public.shared_entries_lock_accepted();

-- Proposes an entry to friend p_friend_id. p_they_owe: the friend owes the
-- caller (else the caller owes the friend). Retrying with the same
-- p_client_ref returns the row the first call made.
create function public.add_shared_entry(
  p_client_ref text,
  p_friend_id uuid,
  p_they_owe boolean,
  p_amount_minor bigint,
  p_currency text,
  p_entry_date date,
  p_due_date date default null,
  p_note text default null,
  p_is_opening boolean default false
)
returns public.shared_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_friendship uuid;
  v_row public.shared_entries;
begin
  if v_me is null then
    raise exception 'not_signed_in';
  end if;

  select * into v_row
  from public.shared_entries e
  where e.created_by = v_me and e.client_ref = p_client_ref;
  if found then
    return v_row;
  end if;

  select f.id into v_friendship
  from public.friendships f
  where f.status = 'accepted'
    and least(f.requester_id, f.addressee_id) = least(v_me, p_friend_id)
    and greatest(f.requester_id, f.addressee_id) = greatest(v_me, p_friend_id);
  if v_friendship is null then
    raise exception 'not_friends';
  end if;

  insert into public.shared_entries (
    friendship_id, created_by, client_ref, owed_by, owed_to, amount_minor,
    currency, entry_date, due_date, note, is_opening
  ) values (
    v_friendship, v_me, p_client_ref,
    case when p_they_owe then p_friend_id else v_me end,
    case when p_they_owe then v_me else p_friend_id end,
    p_amount_minor, upper(p_currency), p_entry_date, p_due_date,
    nullif(btrim(p_note), ''), p_is_opening
  )
  returning * into v_row;
  return v_row;
end;
$$;

-- The creator changes their own entry while it's pending — or after it was
-- rejected, which proposes it again. Accepted entries can't change.
create function public.edit_shared_entry(
  p_client_ref text,
  p_they_owe boolean,
  p_amount_minor bigint,
  p_currency text,
  p_entry_date date,
  p_due_date date default null,
  p_note text default null
)
returns public.shared_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_row public.shared_entries;
  v_friend uuid;
begin
  select * into v_row
  from public.shared_entries e
  where e.created_by = v_me and e.client_ref = p_client_ref
  for update;
  if not found then
    raise exception 'entry_not_found';
  end if;
  if v_row.status = 'accepted' then
    raise exception 'entry_locked';
  end if;

  v_friend := case when v_row.owed_by = v_me then v_row.owed_to else v_row.owed_by end;
  update public.shared_entries
  set owed_by = case when p_they_owe then v_friend else v_me end,
      owed_to = case when p_they_owe then v_me else v_friend end,
      amount_minor = p_amount_minor,
      currency = upper(p_currency),
      entry_date = p_entry_date,
      due_date = p_due_date,
      note = nullif(btrim(p_note), ''),
      status = 'pending',
      version = v_row.version + 1,
      updated_at = now(),
      responded_at = null
  where id = v_row.id
  returning * into v_row;
  return v_row;
end;
$$;

-- The creator takes back an entry that isn't accepted. Already gone is
-- fine — a retried delete just finds nothing.
create function public.delete_shared_entry(p_client_ref text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_status text;
begin
  select e.status into v_status
  from public.shared_entries e
  where e.created_by = v_me and e.client_ref = p_client_ref
  for update;
  if not found then
    return;
  end if;
  if v_status = 'accepted' then
    raise exception 'entry_locked';
  end if;
  delete from public.shared_entries
  where created_by = v_me and client_ref = p_client_ref;
end;
$$;

-- The other side's answer, for the version they saw. Answering the same
-- way twice (a retry) returns the row; anything else that no longer fits
-- says why.
create function public.respond_shared_entry(
  p_id uuid,
  p_accept boolean,
  p_expected_version integer
)
returns public.shared_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_row public.shared_entries;
  v_wanted text := case when p_accept then 'accepted' else 'rejected' end;
begin
  select * into v_row
  from public.shared_entries e
  where e.id = p_id
    and v_me in (e.owed_by, e.owed_to)
    and e.created_by <> v_me
    and exists (
      select 1 from public.friendships f
      where f.id = e.friendship_id and f.status = 'accepted'
    )
  for update;
  if not found then
    raise exception 'entry_not_found';
  end if;
  if v_row.status = v_wanted and v_row.version = p_expected_version then
    return v_row;
  end if;
  if v_row.version <> p_expected_version then
    raise exception 'entry_changed';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'entry_not_pending';
  end if;

  update public.shared_entries
  set status = v_wanted, responded_at = now()
  where id = v_row.id
  returning * into v_row;
  return v_row;
end;
$$;

revoke execute on function public.shared_entries_lock_accepted() from public, anon, authenticated;
revoke execute on function public.add_shared_entry(text, uuid, boolean, bigint, text, date, date, text, boolean) from public, anon;
revoke execute on function public.edit_shared_entry(text, boolean, bigint, text, date, date, text) from public, anon;
revoke execute on function public.delete_shared_entry(text) from public, anon;
revoke execute on function public.respond_shared_entry(uuid, boolean, integer) from public, anon;
grant execute on function public.add_shared_entry(text, uuid, boolean, bigint, text, date, date, text, boolean) to authenticated;
grant execute on function public.edit_shared_entry(text, boolean, bigint, text, date, date, text) to authenticated;
grant execute on function public.delete_shared_entry(text) to authenticated;
grant execute on function public.respond_shared_entry(uuid, boolean, integer) to authenticated;

-- Live updates while Connector is open; the background job polls.
alter publication supabase_realtime add table public.shared_entries;
