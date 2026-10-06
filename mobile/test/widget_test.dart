import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/features/task_editor.dart';

void main() {
  testWidgets('빈 제목은 저장되지 않음', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TaskEditor(initialDate: DateTime(2026, 10, 10))),
    );
    await tester.scrollUntilVisible(
      find.text('저장'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('제목을 입력해주세요'), findsOneWidget);
  });
}
