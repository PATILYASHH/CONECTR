# What & why

<!-- Link the issue this addresses. PRs without a linked issue are fine for docs. -->

Closes #

## Changes

-

## Checklist

<!-- Delete rows that don't apply, but read them first. These are the rules
     from CONTRIBUTING.md. -->

- [ ] Doesn't touch XPENC's internals: only the backup file in the shared folder
- [ ] No secrets, keys, tokens or `dart_define.local.json` committed
- [ ] Database change? New migration file, with RLS enabled and policies
- [ ] Sync rule change? Tests in `test/sync_rules_test.dart`

## Verification

- [ ] `flutter analyze` clean
- [ ] `flutter test` green (new behavior has new tests)
