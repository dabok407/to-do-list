import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/task_controller.dart';
import '../l10n/app_strings.dart';
import '../services/subscription_service.dart';
import 'backup_screen.dart';
import 'notification_privacy_setting.dart';
import 'privacy_card.dart';
import 'settings_widgets.dart';
import 'store_policy_links.dart';

class SettingsPanel extends StatelessWidget {
  final TaskController controller;
  final SubscriptionService subscription;
  final bool busy;
  final VoidCallback openPro,
      requestPermission,
      openDeviceSettings,
      requestExactPermission,
      testReminder;
  final ValueChanged<String> setLanguage;
  const SettingsPanel({
    super.key,
    required this.controller,
    required this.subscription,
    required this.busy,
    required this.openPro,
    required this.setLanguage,
    required this.requestPermission,
    required this.openDeviceSettings,
    required this.requestExactPermission,
    required this.testReminder,
  });

  Future<T?> _sheet<T>(BuildContext context, String title, Widget child) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder: (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .82,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              24 + MediaQuery.paddingOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.of(sheetContext).t('닫기'),
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      );

  Future<void> _language(BuildContext context) async {
    final s = AppStrings.of(context);
    final selected = await _sheet<String>(
      context,
      s.t('언어'),
      Builder(
        builder: (sheetContext) => RadioGroup<String>(
          groupValue: controller.localeController.preference,
          onChanged: (value) {
            if (value != null) Navigator.pop(sheetContext, value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                value: 'system',
                title: Text(s.t('기기 설정 사용')),
                contentPadding: EdgeInsets.zero,
              ),
              const RadioListTile<String>(
                value: 'ko',
                title: Text('한국어'),
                contentPadding: EdgeInsets.zero,
              ),
              const RadioListTile<String>(
                value: 'en',
                title: Text('English'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null &&
        context.mounted &&
        selected != controller.localeController.preference) {
      setLanguage(selected);
    }
  }

  void _notifications(BuildContext context) {
    final s = AppStrings.of(context);
    void action(VoidCallback callback) {
      // Dismiss before opening system screens or Pro so navigation remains clear.
      Navigator.pop(context);
      callback();
    }

    _sheet<void>(
      context,
      s.t('알림 설정·테스트'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.t('배너·소리·진동은 기기의 알림 설정을 따라요.'),
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: settingsMuted,
            ),
          ),
          const SizedBox(height: 18),
          SettingsGroup(
            children: [
              SettingsMenuRow(
                key: const Key('request-notification-permission'),
                icon: Icons.notifications_active_outlined,
                title: s.t('알림 권한 설정'),
                onTap: () => action(requestPermission),
              ),
              SettingsMenuRow(
                key: const Key('open-device-notification-settings'),
                icon: Icons.tune_rounded,
                title: s.t('기기 알림 설정 열기'),
                onTap: () => action(openDeviceSettings),
              ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                SettingsMenuRow(
                  icon: Icons.alarm_on_outlined,
                  title: s.t('Android 정확한 알림 설정'),
                  onTap: () => action(requestExactPermission),
                ),
              SettingsMenuRow(
                key: const Key('test-notification'),
                icon: Icons.notifications_none_rounded,
                title: s.t('10초 뒤 테스트 알림'),
                onTap: () => action(testReminder),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            s.t('알림 제목 표시를 끄면 앱 이름과 안내 문구만 표시해요. 알림 시각과 소리 설정은 유지돼요.'),
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: settingsMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            s.t(
              '미완료 재알림은 기본 매일 한 번, 예정 시간과 같은 시각입니다. 각 할 일의 수정 화면에서 간격·시각을 바꾸거나 끌 수 있어요. 미루기는 선택한 시간까지 기다립니다. 진행 중 확인은 30분 뒤, 작은 시작 확인은 5분 뒤입니다. 배너 표시 여부는 기기 알림 권한·집중 모드·배터리 설정을 따릅니다.',
            ),
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: settingsMuted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final language = switch (controller.localeController.preference) {
      'ko' => '한국어',
      'en' => 'English',
      _ => s.t('기기 설정 사용'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          children: [
            SettingsMenuRow(
              icon: Icons.workspace_premium_outlined,
              title: s.t(
                subscription.paidAccess
                    ? '투두닉 Pro 이용 중'
                    : subscription.trialActive
                    ? '전체 기능 7일 체험 중'
                    : '무료 캘린더 이용 중',
              ),
              subtitle: s.t('연간 구독 · 구매 복원 · 구독 관리'),
              onTap: busy ? null : openPro,
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          title: s.t('알림'),
          children: [
            NotificationPrivacySetting(controller: controller, compact: true),
            SettingsMenuRow(
              key: const Key('notification-settings'),
              icon: Icons.notifications_none_rounded,
              title: s.t('알림 설정·테스트'),
              subtitle: s.t('권한 확인과 테스트 알림'),
              onTap: busy ? null : () => _notifications(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          title: s.t('데이터·사용 환경'),
          children: [
            SettingsMenuRow(
              key: const Key('backup-settings'),
              icon: Icons.folder_outlined,
              title: s.t('백업·복원'),
              subtitle: s.t('주 1회 자동 백업 · 최신 백업 1개 보관'),
              onTap: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BackupScreen(controller: controller),
                      ),
                    ),
            ),
            SettingsMenuRow(
              key: const Key('language-setting'),
              icon: Icons.language_rounded,
              title: s.t('언어'),
              value: language,
              onTap: busy ? null : () => _language(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          title: s.t('지원·앱 정보'),
          children: [
            SettingsMenuRow(
              key: const Key('privacy-details'),
              icon: Icons.shield_outlined,
              title: s.t('나의 일정은, 나의 기기에만'),
              subtitle: s.t('데이터 보관과 개인정보 안내'),
              onTap: () =>
                  _sheet<void>(context, s.t('개인정보 보호'), const PrivacyCard()),
            ),
            const StorePolicyLinks(grouped: true),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
