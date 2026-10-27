import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import 'feedback_snackbar.dart';
import 'settings_widgets.dart';

/// Public documentation only. Opening these links never includes task data.
class StorePolicyLinks extends StatelessWidget {
  final Future<bool> Function(Uri)? open;
  final bool grouped;
  const StorePolicyLinks({super.key, this.open, this.grouped = false});

  static const site = 'https://dabok407.github.io/to-do-list';
  static const appleTerms =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  Future<void> _open(BuildContext context, Uri uri) async {
    var success = false;
    try {
      success =
          await (open?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      // A missing browser or temporary platform error must not close the app.
    }
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        feedbackSnackBar(
          content: Text(
            AppStrings.of(context).t('브라우저를 열지 못했어요. 잠시 후 다시 시도해주세요.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final suffix = strings.isEnglish ? '-en' : '';
    final documents = <String, String>{
      '고객 지원': '$site/support$suffix.html',
      '개인정보처리방침': '$site/privacy$suffix.html',
      '이용약관': defaultTargetPlatform == TargetPlatform.iOS
          ? appleTerms
          : '$site/terms$suffix.html',
    };
    if (grouped) {
      const icons = [
        Icons.help_outline_rounded,
        Icons.policy_outlined,
        Icons.description_outlined,
      ];
      return Column(
        children: [
          for (var i = 0; i < documents.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 58,
                color: Color(0xffecefec),
              ),
            SettingsMenuRow(
              icon: icons[i],
              title: strings.t(documents.keys.elementAt(i)),
              onTap: () =>
                  _open(context, Uri.parse(documents.values.elementAt(i))),
            ),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final document in documents.entries)
          TextButton(
            onPressed: () => _open(context, Uri.parse(document.value)),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            child: Text(strings.t(document.key)),
          ),
      ],
    );
  }
}
