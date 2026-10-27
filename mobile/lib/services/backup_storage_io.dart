import 'dart:io';

import 'package:path/path.dart' as path;

import '../data/backup_snapshot.dart';
import 'backup_storage_base.dart';

BackupStorage createBackupStorage(String Function() databasePath) =>
    FileBackupStorage(
      path.join(path.dirname(databasePath()), 'todoniq-backups'),
    );

class FileBackupStorage implements BackupStorage {
  final String directoryPath;
  FileBackupStorage(this.directoryPath);
  File get latestFile => File(path.join(directoryPath, 'latest.todoniq.json'));
  @override
  bool get supported => true;
  @override
  Future<String?> readLatest() async {
    final file = latestFile;
    if (!await file.exists()) return null;
    if (await file.length() > BackupSnapshot.maxBytes) {
      throw const FormatException('Backup exceeds the size limit');
    }
    return file.readAsString();
  }

  @override
  Future<void> writeLatest(String contents) async {
    await Directory(directoryPath).create(recursive: true);
    final temporary = File(path.join(directoryPath, 'latest.pending'));
    // The service holds a database lease across this whole operation so UI and
    // headless workers cannot replace the same path concurrently.
    try {
      await temporary.writeAsString(contents, flush: true);
      // The destination is replaced by rename on both supported mobile OSes.
      // Never delete the current backup first: a write/rename error keeps it.
      await temporary.rename(latestFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
