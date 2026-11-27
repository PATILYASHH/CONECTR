-- Backup destinations: GitHub, Google Drive or ExoCloud, chosen once per
-- account — and ExoCloud itself, backups kept on ExoSynk's Supabase.
--
-- Paste into Supabase dashboard → SQL Editor → Run, once, after the
-- earlier migrations. Re-running fails on "already exists" instead of
-- silently changing anything.
--
-- Design: docs/superpowers/specs/2026-10-28-google-drive-and-login-design.md
-- and its 2026-11-27 addendum (three destinations, ExoCloud).
--
-- ExoCloud stores only ciphertext. Each backup is encrypted on the phone
-- with a random key that never leaves the user's phones (they keep a
-- recovery key). The server can list, count and delete backups, never read
-- them.

-- ---------------------------------------------------------------------------
-- account_settings: one row per account, readable by its owner only — not a
-- profiles column, since friends (pending and declined included) can read
-- profiles.

create table public.account_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  backup_destination text not null
    constraint backup_destination_value
      check (backup_destination in ('github', 'google_drive', 'exocloud')),
  -- HMAC of a fixed label under the ExoCloud key: lets a new phone check a
  -- typed recovery key before using it. Reveals nothing about the key.
  exocloud_key_check text
    constraint exocloud_key_check_length
      check (char_length(exocloud_key_check) between 16 and 128),
  updated_at timestamptz not null default now()
);

alter table public.account_settings enable row level security;

revoke all on public.account_settings from anon, authenticated;
grant select, insert, update (backup_destination, exocloud_key_check, updated_at)
  on public.account_settings to authenticated;

create policy "Users read their own settings"
  on public.account_settings for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users create their own settings"
  on public.account_settings for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users update their own settings"
  on public.account_settings for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- ExoCloud storage: a private bucket, one folder per user (`<user id>/…`),
-- 10 MB per backup, encrypted bytes only.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exocloud', 'exocloud', false, 10485760, array['application/octet-stream']);

-- Objects in a user's folder, for the insert limit below. Security definer
-- so the policy doesn't evaluate storage.objects' own policies again.
create function public.exocloud_object_count(p_user uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from storage.objects
  where bucket_id = 'exocloud'
    and (storage.foldername(name))[1] = p_user::text;
$$;
revoke all on function public.exocloud_object_count(uuid) from public, anon;
grant execute on function public.exocloud_object_count(uuid) to authenticated;

create policy "ExoCloud: read own folder"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'exocloud'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Retention keeps 10 committed backups; 20 leaves room for uploads in
-- flight, and caps what an uncommitted pile-up could cost.
create policy "ExoCloud: upload to own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'exocloud'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.exocloud_object_count((select auth.uid())) < 20
  );

create policy "ExoCloud: delete from own folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'exocloud'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- exocloud_backups: one row per committed backup. Its created_at is the
-- server's time — what "newest" means, never a phone's clock. Rows are only
-- ever written by exocloud_commit.

create table public.exocloud_backups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  object_path text not null unique,
  created_at timestamptz not null default clock_timestamp(),
  size_bytes integer not null check (size_bytes between 1 and 10485760),
  device_id text not null check (char_length(device_id) between 1 and 64),
  device_name text not null check (char_length(device_name) between 1 and 64),
  backup_modified_at timestamptz not null,
  source_file text not null check (char_length(source_file) <= 255),
  -- Git blob sha of the plaintext, so a phone can tell "identical to the
  -- latest" without downloading it.
  content_sha text not null check (content_sha ~ '^[0-9a-f]{40}$')
);

create index exocloud_backups_user_created
  on public.exocloud_backups (user_id, created_at desc);

alter table public.exocloud_backups enable row level security;
revoke all on public.exocloud_backups from anon, authenticated;
grant select on public.exocloud_backups to authenticated;

create policy "Users read their own ExoCloud backups"
  on public.exocloud_backups for select to authenticated
  using (user_id = (select auth.uid()));

-- Commits an uploaded object as the new latest backup — but only if the
-- latest is still p_replacing (null: there was none). Two phones racing
-- can't both win: the loser gets `exocloud_conflict`, deletes its object,
-- and looks again next run. Returns the new row and the object paths that
-- fell out of retention (the newest 10 are kept), for the phone to delete.
create function public.exocloud_commit(
  p_object_path text,
  p_replacing uuid,
  p_size_bytes integer,
  p_device_id text,
  p_device_name text,
  p_backup_modified_at timestamptz,
  p_source_file text,
  p_content_sha text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_latest uuid;
  v_row public.exocloud_backups;
  v_removed text[];
begin
  if v_user is null then
    raise exception 'not_signed_in';
  end if;
  if split_part(p_object_path, '/', 1) <> v_user::text then
    raise exception 'exocloud_bad_path';
  end if;
  if not exists (
    select 1 from storage.objects
    where bucket_id = 'exocloud' and name = p_object_path
  ) then
    raise exception 'exocloud_missing_object';
  end if;

  -- One commit per account at a time.
  perform pg_advisory_xact_lock(hashtextextended('exocloud:' || v_user::text, 0));

  select id into v_latest from public.exocloud_backups
  where user_id = v_user
  order by created_at desc
  limit 1;
  if v_latest is distinct from p_replacing then
    raise exception 'exocloud_conflict';
  end if;

  insert into public.exocloud_backups (
    user_id, object_path, size_bytes, device_id, device_name,
    backup_modified_at, source_file, content_sha
  ) values (
    v_user, p_object_path, p_size_bytes, p_device_id, p_device_name,
    p_backup_modified_at, p_source_file, p_content_sha
  )
  returning * into v_row;

  with old as (
    select id from public.exocloud_backups
    where user_id = v_user
    order by created_at desc
    offset 10
  ),
  gone as (
    delete from public.exocloud_backups b
    using old
    where b.id = old.id
    returning b.object_path
  )
  select coalesce(array_agg(object_path), '{}') into v_removed from gone;

  return jsonb_build_object(
    'backup', to_jsonb(v_row),
    'removed', to_jsonb(v_removed)
  );
end;
$$;

revoke all on function public.exocloud_commit(
  text, uuid, integer, text, text, timestamptz, text, text
) from public, anon;
grant execute on function public.exocloud_commit(
  text, uuid, integer, text, text, timestamptz, text, text
) to authenticated;
