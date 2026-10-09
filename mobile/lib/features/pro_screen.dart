import 'package:flutter/material.dart';

import '../services/subscription_service.dart';
import 'privacy_card.dart';

class ProScreen extends StatefulWidget {
  final SubscriptionService subscription;
  const ProScreen({super.key, required this.subscription});
  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  @override
  void initState() {
    super.initState();
    widget.subscription.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.subscription,
    builder: (context, _) {
      final s = widget.subscription;
      return Scaffold(
        appBar: AppBar(title: const Text('한걸음 Pro')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '기억하는 일에서\n실행하는 일까지',
              style: TextStyle(
                fontSize: 28,
                height: 1.3,
                fontWeight: FontWeight.w600,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.trialActive
                  ? '처음 7일은 모든 기능을 사용할 수 있어요.\n체험만으로 자동 결제되지 않아요.'
                  : '캘린더와 메모는 무료로.\n알림·미루기·통계는 Pro로 계속하세요.',
            ),
            const SizedBox(height: 24),
            const Text(
              '무료로 계속',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('캘린더 · 할 일과 메모 작성·수정·삭제 · 반복 일정 · 완료와 해제 · 위젯 일정 보기'),
            const SizedBox(height: 24),
            const Text(
              '7일 체험 후 Pro',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '예정 알림 · 미완료 재알림 · 미루기 · 지금 시작·5분 실행 보조 · 30일·90일 통계 · 분류별 분석',
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xfff1f2f4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.active ? 'Pro 이용 중' : '연간 구독',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.price == null ? '스토어 가격을 확인해주세요' : '${s.price} / 1년',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.active && s.autoRenewing == false
                        ? '자동 갱신이 해제되어 있어요. 이용 기간까지 Pro를 사용할 수 있어요.'
                        : '1년에 한 번 결제 · 해지 전까지 자동 갱신',
                  ),
                  if (s.expires != null)
                    Text(
                      '이용 기간: ${s.expires!.year}.${s.expires!.month}.${s.expires!.day}까지',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (s.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(s.message!, key: const Key('billing-message')),
              ),
            FilledButton(
              onPressed: s.busy || s.pending || !s.available || s.active
                  ? null
                  : s.purchase,
              child: Text(
                s.busy
                    ? '스토어 확인 중…'
                    : s.pending
                    ? '결제 승인 대기 중'
                    : s.active
                    ? 'Pro 이용 중'
                    : s.price == null
                    ? '가격 확인 필요'
                    : '${s.price}에 연간 구독',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: s.busy ? null : s.restore,
                  child: const Text('구매 복원'),
                ),
                TextButton(
                  onPressed: s.busy ? null : s.manage,
                  child: const Text('구독 관리·해지'),
                ),
                TextButton(
                  onPressed: s.busy ? null : s.refresh,
                  child: const Text('다시 확인'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '결제는 Apple 또는 Google 계정으로 진행됩니다. 표시된 금액이 매년 청구되며, 스토어에서 해지할 수 있습니다. 해지 후에도 결제한 기간까지 이용할 수 있습니다. 다른 플랫폼의 구매는 서로 공유되지 않습니다. 구독 기능은 마지막 스토어 확인 후 최대 24시간 오프라인으로 사용할 수 있습니다. 이후 다시 확인하려면 인터넷이 필요합니다.',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xff626660),
              ),
            ),
            const SizedBox(height: 24),
            const PrivacyCard(),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('이용약관·개인정보'),
                  content: const SingleChildScrollView(
                    child: Text(
                      '할 일과 실행 기록은 기기에만 저장합니다. 앱 운영자가 수집하는 회원정보나 클라우드 데이터는 없습니다. 기기 변경 또는 앱 삭제 시 기록이 사라질 수 있습니다.\n\nPro는 1년 단위로 자동 갱신되는 디지털 기능 이용권입니다. 가격과 결제 조건은 구매 확인 화면을 따릅니다. 결제·환불·해지는 구매한 스토어에서 관리합니다. 구매를 복원하려면 같은 스토어 계정을 사용하세요.\n\n첫 실행부터 7일간 전체 기능을 체험합니다. 체험은 자동 결제로 전환되지 않습니다. 구독이 만료되면 알림·미루기·실행 보조·통계가 잠기며 캘린더·메모·완료 기록은 유지됩니다. 스토어에서 마지막으로 확인한 구독은 최대 24시간 오프라인으로 이용할 수 있습니다. 이후 인터넷에 연결하여 구독을 다시 확인해주세요.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              ),
              child: const Text('이용약관·개인정보 안내'),
            ),
          ],
        ),
      );
    },
  );
}
