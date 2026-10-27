import 'package:flutter/material.dart';

import '../app/task_controller.dart';
import '../l10n/app_strings.dart';
import '../services/notification_privacy.dart';
import 'feedback_snackbar.dart';
import 'settings_widgets.dart';

class NotificationPrivacySetting extends StatefulWidget {
  final TaskController controller;
  final bool compact;
  const NotificationPrivacySetting({
    super.key,
    required this.controller,
    this.compact = false,
  });
  @override
  State<NotificationPrivacySetting> createState() =>
      _NotificationPrivacySettingState();
}

class _NotificationPrivacySettingState
    extends State<NotificationPrivacySetting> {
  late Future<bool> preference;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    preference = NotificationPrivacy(widget.controller.repository).load();
    widget.controller.addListener(reloadPreference);
  }

  void reloadPreference() {
    setState(() {
      preference = NotificationPrivacy(widget.controller.repository).load();
    });
  }

  @override
  void didUpdateWidget(NotificationPrivacySetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(reloadPreference);
      widget.controller.addListener(reloadPreference);
      preference = NotificationPrivacy(widget.controller.repository).load();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(reloadPreference);
    super.dispose();
  }

  Future<void> change(bool show) async {
    setState(() => busy = true);
    try {
      await widget.controller.setNotificationTitles(show);
      if (mounted) {
        setState(
          () =>
              preference = NotificationPrivacy(widget.controller.repository)
                  .load(),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          feedbackSnackBar(
            content: Text(
              AppStrings.of(context).t('설정을 저장하지 못했어요. 다시 시도해주세요.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return FutureBuilder<bool>(
      future: preference,
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            key: const Key('notification-title-toggle'),
            secondary: widget.compact
                ? const SettingsIcon(Icons.visibility_outlined)
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              s.t('알림에 할 일 제목 표시'),
              style: widget.compact
                  ? const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)
                  : null,
            ),
            subtitle: Text(
              s.t(
                state.data == false ? '제목 숨김 · 앱에서 내용을 확인해요' : '제목 표시 · 기본 설정',
              ),
              style: widget.compact
                  ? const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: settingsMuted,
                    )
                  : null,
            ),
            value: state.data ?? true,
            onChanged:
                busy ||
                    state.connectionState != ConnectionState.done ||
                    !state.hasData
                ? null
                : change,
          ),
          if (!widget.compact || state.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                s.t(
                  state.hasError
                      ? '설정을 불러오지 못했어요. 설정 화면을 다시 열어주세요.'
                      : '끄면 알림에 앱 이름과 안내 문구만 표시해요. 알림 시각과 소리 설정은 유지돼요.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
