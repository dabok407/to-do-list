import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffdfe2e6)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 24),
        const SizedBox(height: 12),
        Text(
          AppStrings.of(context).t('나의 일정은, 나의 기기에만'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.of(context).t(
            '할 일·메모·실행 기록을 운영자 서버로 보내지 않아요. 회원가입, 광고, 행동 추적 없이 개인의 일상을 기록하세요.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AppStrings.of(context).t(
            '기본 캘린더와 메모는 오프라인에서도 사용할 수 있어요. 구매·복원·구독 확인은 Apple 또는 Google 스토어와 통신합니다. 앱 삭제나 기기 변경 시 기록이 사라질 수 있어요.',
          ),
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Color(0xff626873),
          ),
        ),
      ],
    ),
  );
}
