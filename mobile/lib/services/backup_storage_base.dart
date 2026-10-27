abstract class BackupStorage {
  bool get supported;
  Future<String?> readLatest();

  /// Replace the one stable file only after all bytes have been flushed.
  Future<void> writeLatest(String contents);
}

/// Also used by the browser preview and tests without touching real files.
class MemoryBackupStorage implements BackupStorage {
  String? contents;
  @override
  bool get supported => true;
  @override
  Future<String?> readLatest() async => contents;
  @override
  Future<void> writeLatest(String contents) async => this.contents = contents;
}
