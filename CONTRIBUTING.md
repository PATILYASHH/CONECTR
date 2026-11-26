# Contributing to Connector

Thanks for your interest in making Connector better. Connector is the online
companion to [XPENC](https://github.com/PATILYASHH/XPENC); read the
[README](README.md) first for how the two apps fit together.

## Ways to contribute

| You want to… | Start here |
|---|---|
| Report a bug | [Open a bug report](../../issues/new?template=bug_report.yml) |
| Request a feature | [Open a feature request](../../issues/new?template=feature_request.yml) |
| Report a security problem | [SECURITY.md](SECURITY.md), **not** a public issue |
| Improve docs | PRs welcome, no issue needed |
| Fix a bug / build a feature | Comment on the issue first so work isn't duplicated |

## Development setup

You need your own Supabase project and GitHub OAuth App. The README's
[Build from source](README.md#build-from-source) section walks
through it. Then:

```sh
git clone https://github.com/PATILYASHH/CONECTR.git
cd CONECTR
cp dart_define.example.json dart_define.local.json   # fill in your values
flutter pub get
flutter run --dart-define-from-file=dart_define.local.json
```

**Toolchain:** the Flutter **beta** channel. `pubspec.lock` needs Flutter
≥ 3.44 and Dart ≥ 3.13 beta.

### Checks

```sh
flutter analyze
flutter test
```

Both run in CI on every push and pull request.

## Rules that keep Connector trustworthy

These are invariants, not preferences. PRs that break them will not be merged:

1. **Never touch XPENC's internals.** Connector only reads and writes the
   backup file in the shared folder. It never opens XPENC's database or
   private storage.
2. **No secrets in the repo.** Supabase URL and anon key come from
   `--dart-define` only. Never commit `dart_define.local.json`,
   `android/key.properties`, a keystore, or a token. Never add a Supabase
   `service_role` key anywhere in the app.
3. **Database changes are new migrations.** Add a new timestamped file under
   `supabase/migrations/`; never edit one that has already shipped. Every new
   table gets Row Level Security, enabled and with policies, in the same file.
4. **Never push over another phone's backup.** Uploads stay fast-forward only
   (see "Conflict handling" in the README). A change to the sync rules in
   `lib/core/backup/sync_rules.dart` needs tests in `test/sync_rules_test.dart`.
5. **Keep the GitHub token in secure storage.** Use `flutter_secure_storage`.
   Never log the token or write it to a plain file.

## Pull requests

- Keep PRs focused; one change per PR is easiest to review.
- New behavior comes with tests.
- `flutter analyze` is clean and `flutter test` passes.
- By contributing you agree that your contributions are licensed under the
  [MIT License](LICENSE).
