<div align="center">

<img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" width="96" alt="CONECTR icon">

# CONECTR

**by [ExoSynk Labs](https://github.com/ExoSynkLabs)**

[![Release](https://img.shields.io/github/v/release/PATILYASHH/CONECTR?label=release&color=white&labelColor=black)](https://github.com/PATILYASHH/CONECTR/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/PATILYASHH/CONECTR/total?color=white&labelColor=black)](https://github.com/PATILYASHH/CONECTR/releases)
[![CI](https://github.com/PATILYASHH/CONECTR/actions/workflows/ci.yml/badge.svg)](https://github.com/PATILYASHH/CONECTR/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-white?labelColor=black)](LICENSE)
[![Powered by ExoSynk Labs](https://img.shields.io/badge/powered%20by-ExoSynk%20Labs-white?labelColor=black)](https://github.com/ExoSynkLabs)

### The online companion for offline-first apps.
Backup, sync across phones, and friends, so your apps never need the internet themselves.

[⬇️ Download APK](https://github.com/PATILYASHH/CONECTR/releases/latest) · [🌐 ExoSynk Labs](https://exosynk.com/exosynk-labs#conectr) · [🐛 Report a bug](../../issues/new?template=bug_report.yml) · [✨ Request a feature](../../issues/new?template=feature_request.yml)

</div>

> **Your apps stay offline. CONECTR goes online for them.**
> [XPENC](https://github.com/PATILYASHH/XPENC) has no `INTERNET` permission
> and never will. CONECTR is a separate app that moves XPENC's own backup file
> to a **private repo in your own GitHub account** and brings it back on your
> other phones. It never opens XPENC's database.

## Supported apps

| App | What it is | Status |
|---|---|---|
| [XPENC](https://github.com/PATILYASHH/XPENC) | Offline money manager | ✅ Supported |
| [FITNS](https://github.com/Parthmagdum/FITNS) | Fitness app | 🛠️ Planned |
| [PLANR](https://github.com/PATILYASHH/PLANR) | Planner app | 🛠️ Planned |

## Highlights

- ☁️ **Back up where you like.** Pick one per account:
  - **Google Drive** — a visible `XPENC Backup` folder in *your* Drive. Easiest: sign in with Google and you're done.
  - **ExoCloud** — kept by ExoSynk Labs, **end-to-end encrypted** on your phone (only you hold the key). Free during beta.
  - **GitHub** — a private `XPENC-BACKUP` repo in *your* account, with full history. For developers.
- 📱 **Sync across phones.** Pull the latest backup onto another phone, and XPENC takes it in by itself.
- 🛡️ **Never overwrites newer data.** Uploads are fast-forward only: a phone never pushes over another phone's backup it hasn't taken in yet.
- ⏱️ **Auto-sync** in the background, after every XPENC backup or hourly.
- 👥 **Friends & shared entries.** Add friends by exact username and keep a shared owes/dues ledger that's the same on both phones. Every entry is accepted by the other side.
- 🔑 **Sign in with Google, email or GitHub.** Tokens stay in Android's secure storage.

How it all works, and why: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## How it fits together

```
XPENC (offline)          CONECTR (online)               Your choice
───────────────          ────────────────               ───────────
writes its backup  ───▶  reads the file from      ───▶  Google Drive,
to a shared folder       the same folder                ExoCloud, or
                                                        GitHub

takes the backup   ◀───  hands the pulled         ◀───
in by itself             backup to XPENC
```

## Download

Get the APK from **[Releases](https://github.com/PATILYASHH/CONECTR/releases/latest)**:
open the page on your phone, download `connector-<version>.apk` and open it.
Every release ships `SHA256SUMS.txt` to verify the download.

**First run, on each phone:**

1. Sign in (Google, email or GitHub).
2. Connections → XPENC: choose Google Drive, ExoCloud or GitHub. With
   ExoCloud, **save the recovery key** it shows you — your other phones need
   it, and nobody can recover it for you.
3. Point CONECTR at XPENC's `Download/BACKUP XPENC` folder (make a backup in
   XPENC first if the folder doesn't exist yet).
4. Tap **Upload now** on your main phone. On your other phones, CONECTR pulls
   that backup and XPENC takes it in.

## Privacy & security

- With **Google Drive** or **GitHub**, backups live in your own account and no
  ExoSynk server stores them. Drive access is limited to files CONECTR
  created (`drive.file`) — never the rest of your Drive.
- With **ExoCloud**, backups are stored by ExoSynk Labs but encrypted on your
  phone first (AES-256-GCM) with a key that never leaves your phones. ExoSynk
  can't read them. Lose every phone *and* the recovery key, and they're gone.
- Sign-in goes through Supabase Auth.
- CONECTR only reads and writes XPENC's backup file. It never touches XPENC's
  database.
- Drive and GitHub backups are plain JSON in your own account; encrypting
  those too is [on the list](docs/ARCHITECTURE.md#not-built-yet).
- Full details: [Privacy Policy](PRIVACY.md).
- Found a vulnerability? Please follow [SECURITY.md](SECURITY.md) rather than
  opening a public issue.

## Build from source

CONECTR needs a Supabase project (free tier is fine) for sign-in and friends.
To build it yourself, use **your own** project:

1. **Supabase**: create a project at [supabase.com](https://supabase.com) and
   note its **Project URL** and **anon key** (Project Settings → API).
2. **GitHub OAuth App**: GitHub → Settings → Developer settings → OAuth Apps →
   New. Set the callback URL to your Supabase callback
   (`https://<project-ref>.supabase.co/auth/v1/callback`).
3. **Connect them**: in Supabase → Authentication → Providers → GitHub, paste
   the Client ID and Secret. Under URL Configuration, add
   `conectr://login-callback` to the Redirect URLs.
4. **Database**: run each file in [`supabase/migrations/`](supabase/migrations)
   once, in filename order, in the SQL Editor (or `supabase db push`). The
   backup-destinations migration also creates ExoCloud's private storage
   bucket.
5. **Google (optional — sign-in and Drive)**, in a Google Cloud project:
   1. Enable the **Google Drive API**.
   2. OAuth consent screen: External; scopes `openid`, `email`, `profile`,
      `drive.file` (all non-sensitive, no review); **publish to Production** —
      in Testing, Google drops grants after 7 days and auto-sync breaks.
   3. OAuth client, type **Android**: package `com.yash.xpenc.conectr` and the
      SHA-1 of the key your APK is signed with (one client per key — debug
      and release).
   4. OAuth client, type **Web**: its Client ID is `GOOGLE_WEB_CLIENT_ID` in
      `dart_define.local.json`; its Client ID and secret go into Supabase →
      Authentication → Providers → Google.

   Without `GOOGLE_WEB_CLIENT_ID` the app simply hides Google sign-in and
   Drive.
6. **Run**:

   ```sh
   cp dart_define.example.json dart_define.local.json   # fill in your values
   flutter pub get
   flutter run --dart-define-from-file=dart_define.local.json
   ```

Needs the Flutter **beta** channel (Flutter ≥ 3.44, Dart ≥ 3.13).
`dart_define.local.json` is gitignored. The anon key is public by design and
protected by Row Level Security. **Never** put a `service_role` key in the app.

## Contributing

Issues and pull requests are welcome.

📖 [CONTRIBUTING.md](CONTRIBUTING.md) (setup, rules & PR checklist) · 🏗️ [ARCHITECTURE.md](docs/ARCHITECTURE.md) · 🔒 [SECURITY.md](SECURITY.md)

Like it? A ⭐ helps the project more than you'd think.

---

<div align="center">

**[MIT](LICENSE) © 2026 Yash Patil**: GitHub [@PATILYASHH](https://github.com/PATILYASHH) · LinkedIn [in/patilyasshh](https://www.linkedin.com/in/patilyasshh/)

Powered by **[ExoSynk Labs](https://github.com/ExoSynkLabs)** · [exosynk.com](https://exosynk.com) · [More from us](https://exosynk.com/exosynk-labs)

</div>
