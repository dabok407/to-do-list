# Local backup and restore

The installed app supports manual backup, explicit file export/import, and an
optional weekly automatic backup. Backups are available independently of Pro.

## Automatic backup contract

- Off by default. Switching it on writes an initial backup before saving the
  enabled preference.
- After seven elapsed days, the next app reconciliation or permitted background
  refresh replaces the latest backup. iOS and Android control background runtime;
  the app cannot promise execution at an exact weekly time when not opened.
- The stable local file is `todoniq-backups/latest.todoniq.json` beside the app's
  database. A flushed temporary file is renamed over it; the existing backup is
  never deleted first. At rest only the latest backup remains. Its size can change
  as the user's records grow, but there is no accumulating sequence of snapshots.
- The directory inherits the app's existing local-storage backup policy:
  Documents is excluded from device backup on iOS and Android `allowBackup` is
  false. No remote request is made for automatic backup.
- An app uninstall or loss of the device also loses this internal backup. Users
  wanting protection against those events must export a file to their chosen
  destination. An explicitly selected document provider may itself be a cloud
  service; this is separate from automatic local backup.

## File format and restore

The versioned JSON envelope contains an exact payload string and SHA-256 checksum.
The checksum detects accidental file damage; it is neither encryption nor proof
of the file author's identity. The plaintext backup contains task titles, notes,
recurrence patterns and exceptions, occurrence state/history, events, display
language and the notification-title preference. It deliberately excludes purchase
entitlements, trial start dates, device identifiers, automatic-backup preference,
background timestamps and scheduling leases.

Import checks the file size (20 MiB maximum), version, checksum, exact column
allowlist, allowed values, dates, unique keys, row count and foreign-key references
before offering a restore confirmation. A confirmed restore replaces task records
in one SQLite transaction and preserves non-exported current device settings. Any
SQL error rolls the whole restore back. The host must reload language and reconcile
notifications/widgets after a successful restore.

Automatic foreground/background writes use a database lease, so separate engines
do not overwrite the latest file simultaneously. The native iOS document picker
and Android Storage Access Framework handle user-directed file import/export;
neither requests broad storage permission.

## Verification

`flutter test test/backup_service_test.dart` covers round trips, purchase/trial
exclusion, checksum/version/shape/reference rejection, transactional rollback,
initial backup, seven-day boundary, clock rollback, failed writes, concurrent
workers, corrupted local backup recovery, one-file retention and picker
cancellation. Native document-picker interaction still needs an installed-device
pass on each shipping platform.
