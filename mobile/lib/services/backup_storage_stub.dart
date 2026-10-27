import 'backup_storage_base.dart';

BackupStorage createBackupStorage(String Function() databasePath) =>
    _UnavailableBackupStorage();

class _UnavailableBackupStorage implements BackupStorage {
  @override
  bool get supported => false;
  @override
  Future<String?> readLatest() async => null;
  @override
  Future<void> writeLatest(String contents) async =>
      throw UnsupportedError('Local backups require the installed app');
}
