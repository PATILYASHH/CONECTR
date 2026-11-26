# Security Policy

Connector holds a GitHub token that can write to the user's backup repo, and
it moves a file full of financial data. Security reports are taken seriously.

## Supported versions

Only the [latest release](https://github.com/PATILYASHH/CONECTR/releases/latest)
receives security fixes.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Use GitHub's private vulnerability reporting instead:

1. Go to the repository's **Security** tab
2. Click **Report a vulnerability**
3. Describe the issue, steps to reproduce, and impact

You should receive a response within a few days. Once fixed, the report will be
credited (unless you prefer otherwise) in the release notes.

## Scope notes

- In scope: anything that leaks the GitHub token or backup contents, writes to
  a repo other than the user's own `XPENC-BACKUP`, lets one user read or change
  another user's profile, friendships or shared entries (the Row Level Security
  policies in [`supabase/migrations/`](supabase/migrations)), or makes
  Connector read anything of XPENC's beyond the backup file.
- The Supabase **anon key** in a build is public by design and is not a
  vulnerability on its own; a way around the RLS policies with it is.
- Connector never needs a Supabase `service_role` key. If you find one in this
  repo or in a build, that is a vulnerability — please report it.
