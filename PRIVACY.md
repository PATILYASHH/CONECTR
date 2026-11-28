# CONECTR Privacy Policy

_Last updated: 28 November 2026_

CONECTR (shown on phones as "Connector") is an Android app made by
**ExoSynk Labs**. It is the optional online companion to offline apps such as
XPENC: it backs up the backup file those apps write, syncs it between your
phones, and lets you share entries with friends. This policy explains what
CONECTR handles, where it goes, and what it is never used for.

## The short version

- CONECTR only reads and writes the **backup file** your offline app (XPENC)
  exports. It never opens that app's own database.
- Your backups go **where you choose**: your own Google Drive, your own GitHub
  account, or ExoCloud. ExoCloud backups are encrypted on your phone first, so
  ExoSynk Labs cannot read them.
- No ads, no analytics or tracking, and your data is never sold or shared for
  marketing.

## What CONECTR stores, and where

### Your account (Supabase)
To sign you in and connect you with friends, CONECTR uses
[Supabase](https://supabase.com) as its account service. It stores:

- your sign-in identity: the email address and name from Google, GitHub or
  email sign-in;
- the **username** (and optional display name) you choose, which friends use
  to find you;
- your **friend list** and friend requests;
- **shared entries** you create with friends (who owes whom, amount,
  currency, note, status) — visible only to you and that friend;
- your account settings, such as which backup destination you chose.

### Your backups — in the place you choose

- **Google Drive.** Backups are saved as files in an `XPENC Backup` folder in
  *your own* Google Drive. ExoSynk Labs has no copy.
- **GitHub.** Backups are saved to a private `XPENC-BACKUP` repository in
  *your own* GitHub account. ExoSynk Labs has no copy.
- **ExoCloud.** Backups are stored by ExoSynk Labs (on Supabase Storage), but
  they are **encrypted on your phone** with AES-256-GCM before upload, using a
  key that exists only on your phones and in the recovery key you keep. We
  cannot decrypt them. Alongside each encrypted backup we keep: its size, the
  time it was uploaded, the name and a random id of the phone it came from,
  the name and time of the file XPENC wrote, and a fingerprint (hash) used to
  tell whether two backups are identical. ExoCloud keeps your newest 10
  backups and deletes older ones automatically.

### On your phone
Sign-in tokens, the ExoCloud key and sync status are kept in Android's
encrypted secure storage on the device.

## Google user data

When you choose Google sign-in or Google Drive, CONECTR asks Google for:

- **Your basic profile** (`openid`, `email`, `profile`) — only to sign you in
  to your CONECTR account.
- **`drive.file`** — access limited to files CONECTR itself creates. CONECTR
  uses it only to create the `XPENC Backup` folder and to save, list, read and
  delete the backup files in it. It cannot see any other file in your Drive.

Google Drive data is transferred directly between your phone and Google. It
is not sent to ExoSynk Labs' servers, not used for advertising, not sold, not
used to train AI or machine-learning models, and not read by people.

CONECTR's use and transfer of information received from Google APIs adheres
to the [Google API Services User Data
Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements.

You can revoke CONECTR's access to your Google account at any time at
[myaccount.google.com/permissions](https://myaccount.google.com/permissions).

## What we never do

- Sell, rent or trade your data.
- Show ads or use advertising or analytics SDKs.
- Read your backups. (Drive and GitHub backups are in your own accounts;
  ExoCloud backups are encrypted with a key we never receive.)
- Share your data with anyone, except the services named above that make
  CONECTR work (Supabase, and Google or GitHub when you choose them), or when
  required by law.

## Keeping and deleting your data

- **Sign out** in Settings to remove your sign-in, keys and connections from
  that phone.
- **Drive or GitHub backups** are yours: delete them in Google Drive or GitHub
  whenever you like.
- **ExoCloud backups, your account, username, friends and shared entries** are
  kept until you ask us to delete them. To delete your account and everything
  stored with it, open a request on the project's
  [GitHub page](https://github.com/PATILYASHH/CONECTR/issues) or contact
  ExoSynk Labs through [exosynk.com](https://exosynk.com). We'll confirm it's
  your account before deleting.

## Security

Connections use HTTPS. Access to every account's data in Supabase is limited
to that account by row-level security. Security issues can be reported
privately as described in [SECURITY.md](SECURITY.md).

## Children

CONECTR is not directed at children under 13 and does not knowingly collect
their data.

## Changes

If this policy changes, the new version will be published here with a new
date. Material changes will also be mentioned in the app's release notes.

## Contact

ExoSynk Labs — [exosynk.com](https://exosynk.com) ·
[github.com/PATILYASHH/CONECTR](https://github.com/PATILYASHH/CONECTR)
