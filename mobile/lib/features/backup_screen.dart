import 'package:flutter/material.dart';

import '../app/task_controller.dart';
import '../l10n/app_strings.dart';
import '../services/backup_service.dart';
import 'feedback_snackbar.dart';

class BackupScreen extends StatefulWidget {
  final TaskController controller;
  final BackupService? service;
  const BackupScreen({super.key, required this.controller, this.service});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupService? get service => widget.service ?? widget.controller.backups;
  BackupStatus? status;
  bool busy = false;
  String? error;
  AppStrings get s => AppStrings.of(context);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await service?.loadStatus();
      if (mounted) setState(() => status = value);
    } catch (_) {
      if (mounted) setState(() => error = '백업 상태를 불러오지 못했어요. 다시 시도해주세요.');
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await load();
    } on FormatException {
      if (mounted) {
        setState(
          () => error = '올바른 투두닉 백업 파일이 아니거나 파일이 손상되었어요. 현재 기록은 그대로 유지돼요.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '백업 작업을 마치지 못했어요. 저장 공간과 파일을 확인한 뒤 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(feedbackSnackBar(content: Text(s.t(text))));
    }
  }

  Future<void> restore({required bool fromFile}) => run(() async {
    final snapshot = fromFile
        ? await service!.pickBackup()
        : await service!.latestBackup();
    if (snapshot == null || !mounted) return;
    final date = snapshot.createdAt.toLocal();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('이 백업으로 복원할까요?')),
        content: Text(
          s.t(
            '{date} {time} · 할 일 {count}개\n현재 할 일과 완료 기록이 이 백업 내용으로 교체돼요. 구독·체험 상태는 바뀌지 않아요.',
            args: {
              'date': s.date(date),
              'time': s.time(date),
              'count': snapshot.taskCount,
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.t('취소')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('복원')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.restoreBackup(snapshot);
    notice('백업을 복원했어요.');
  });
  @override
  Widget build(BuildContext context) {
    final available = service?.available ?? false;
    final stamp = status?.lastBackupAt?.toLocal();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('백업·복원'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              s.t('내 기록을 기기에 보관해요'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(s.t('할 일·메모·완료 기록을 백업해요. 자동 백업은 외부 서버로 전송되지 않아요.')),
            const SizedBox(height: 24),
            SwitchListTile.adaptive(
              key: const Key('automatic-backup-toggle'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('주 1회 자동 백업')),
              subtitle: Text(s.t('최신 백업 1개만 보관')),
              value: status?.enabled ?? false,
              onChanged: available && !busy && status != null
                  ? (value) => run(() => service!.setAutomatic(value))
                  : null,
            ),
            Text(
              s.t(
                '최신 백업 파일로 교체하므로 백업본이 쌓이지 않아요. 기록량에 따라 파일 하나의 크기는 달라질 수 있어요.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              s.t(
                '7일이 지나면 앱을 열거나 시스템이 백그라운드 실행을 허용할 때 갱신해요. 앱을 오래 열지 않으면 갱신이 늦어질 수 있어요.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 36),
            Text(s.t('최근 백업'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              stamp == null
                  ? s.t(
                      status?.invalidBackup == true
                          ? '기기 백업 파일을 읽을 수 없어요. 새 백업을 만들어주세요.'
                          : '아직 백업이 없어요',
                    )
                  : '${s.date(stamp)} ${s.time(stamp)}',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('create-local-backup'),
              onPressed: available && !busy
                  ? () => run(() async {
                      await service!.createBackup();
                      notice('최신 백업을 저장했어요.');
                    })
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(s.t('지금 백업하기')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: available && !busy
                  ? () => run(() async {
                      if (await service!.exportBackup()) {
                        notice('백업 파일을 저장했어요.');
                      }
                    })
                  : null,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(s.t('백업 파일 내보내기')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: available && !busy
                  ? () => restore(fromFile: true)
                  : null,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(s.t('파일에서 복원')),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: available && !busy && (status?.hasBackup ?? false)
                  ? () => restore(fromFile: false)
                  : null,
              child: Text(s.t('기기의 최신 백업으로 복원')),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  s.t(error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!available) Text(s.t('백업·복원은 설치된 앱에서 사용할 수 있어요.')),
            const SizedBox(height: 16),
            Text(
              s.t(
                '내보낸 파일에는 할 일과 메모가 포함돼요. 파일은 암호화되지 않으므로 저장 위치와 공유 대상을 확인해주세요.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              s.t(
                '기기를 잃어버리거나 앱을 삭제하면 기기 안의 백업도 사라질 수 있어요. 기기 변경 전에는 파일을 내보내 별도로 보관해주세요. 내보내기는 직접 선택한 저장 위치를 사용해요.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
