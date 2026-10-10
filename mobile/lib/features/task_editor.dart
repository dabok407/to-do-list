import 'package:flutter/material.dart';

import '../domain/task.dart';
import '../l10n/app_strings.dart';

class TaskEditor extends StatefulWidget {
  final Task? task;
  final bool premium;
  final DateTime initialDate;
  const TaskEditor({
    super.key,
    this.task,
    required this.initialDate,
    this.premium = true,
  });
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController title, note, small, interval;
  late DateTime due;
  DateTime? end;
  int priority = 1, monthWeek = 1, countPerWeek = 1;
  int overdueDays = 1;
  int? overdueMinute;
  RepeatUnit repeat = RepeatUnit.none;
  String category = '생활';
  Set<int> weekdays = {};
  AppStrings get strings => AppStrings.of(context);
  @override
  void initState() {
    super.initState();
    final t = widget.task;
    title = TextEditingController(text: t?.title ?? '');
    note = TextEditingController(text: t?.note ?? '');
    small = TextEditingController(text: t?.smallStep ?? '');
    interval = TextEditingController(text: '${t?.interval ?? 1}');
    due =
        t?.due ??
        DateTime(
          widget.initialDate.year,
          widget.initialDate.month,
          widget.initialDate.day,
          DateTime.now().hour + 1,
        );
    end = t?.end;
    priority = t?.priority ?? 1;
    category = t?.category ?? '생활';
    repeat = t?.repeat ?? RepeatUnit.none;
    weekdays = (t?.weekdays ?? [due.weekday]).toSet();
    monthWeek = t?.monthWeek ?? 1;
    countPerWeek = t?.countPerWeek ?? 1;
    overdueDays = t?.overdueDays ?? 1;
    overdueMinute = t?.overdueMinute;
  }

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    small.dispose();
    interval.dispose();
    super.dispose();
  }

  Future<void> pickDate(bool ending) async {
    final value = await showDatePicker(
      context: context,
      initialDate: ending ? end ?? due : due,
      firstDate: ending ? dayOf(due) : DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() {
        if (ending) {
          end = value;
        } else {
          due = DateTime(
            value.year,
            value.month,
            value.day,
            due.hour,
            due.minute,
          );
          if (end != null && end!.isBefore(dayOf(due))) end = null;
        }
      });
    }
  }

  Widget saveButton() => FilledButton(
    onPressed: () {
      if (!form.currentState!.validate()) return;
      if ((repeat == RepeatUnit.weekly ||
              repeat == RepeatUnit.monthlyWeekday) &&
          weekdays.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.t('반복할 요일을 선택해주세요'))));
        return;
      }
      final now = DateTime.now();
      Navigator.pop(
        context,
        Task(
          id: widget.task?.id ?? 't${now.microsecondsSinceEpoch}',
          title: title.text.trim(),
          note: note.text.trim(),
          smallStep: small.text.trim(),
          due: due,
          created: widget.task?.created ?? now,
          priority: priority,
          category: category,
          repeat: repeat,
          interval: int.tryParse(interval.text) ?? 1,
          weekdays: weekdays.toList()..sort(),
          end: repeat == RepeatUnit.none ? null : end,
          monthWeek: monthWeek,
          countPerWeek: countPerWeek,
          groupId: widget.task?.groupId,
          derived: widget.task?.derived ?? false,
          overdueDays: overdueDays,
          overdueMinute: overdueMinute,
        ),
      );
    },
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(strings.t('저장')),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(strings.t(widget.task == null ? '할 일 추가' : '반복·할 일 수정')),
    ),
    bottomNavigationBar: AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: saveButton(),
      ),
    ),
    body: Form(
      key: form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: title,
              autofocus: widget.task == null,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: strings.t('할 일')),
              maxLength: 100,
              validator: (v) => v == null || v.trim().isEmpty
                  ? strings.t('제목을 입력해주세요')
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              itemHeight: null,
              initialValue: category,
              decoration: InputDecoration(labelText: strings.t('분류')),
              items:
                  [
                        '생활',
                        '업무',
                        '건강',
                        '배움',
                        if (!['생활', '업무', '건강', '배움'].contains(category))
                          category,
                      ]
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(strings.category(c)),
                        ),
                      )
                      .toList(),
              onChanged: (v) => setState(() => category = v!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: note,
              decoration: InputDecoration(labelText: strings.t('메모')),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: small,
              enabled: widget.premium,
              decoration: InputDecoration(
                labelText: strings.t('작은 첫걸음'),
                hintText: strings.t('운동복 입고 5분만 움직이기'),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => pickDate(false),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(strings.date(due)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final value = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(due),
                );
                if (value != null && mounted) {
                  setState(
                    () => due = DateTime(
                      due.year,
                      due.month,
                      due.day,
                      value.hour,
                      value.minute,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.schedule),
              label: Text(strings.time(due)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              isExpanded: true,
              itemHeight: null,
              initialValue: priority,
              decoration: InputDecoration(labelText: strings.t('우선순위')),
              items: [
                DropdownMenuItem(value: 0, child: Text(strings.t('낮음'))),
                DropdownMenuItem(value: 1, child: Text(strings.t('보통'))),
                DropdownMenuItem(value: 2, child: Text(strings.t('높음'))),
              ],
              onChanged: (v) => setState(() => priority = v!),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              key: const Key('overdue-settings'),

              title: Text(strings.t('미완료 재알림')),
              subtitle: Text(
                overdueDays == 0
                    ? strings.t('꺼짐')
                    : '${overdueDays == 1 ? strings.t('매일') : strings.t('{days}일마다', args: {'days': overdueDays})} · ${overdueMinute == null ? strings.t('예정 시간과 같게') : strings.time(DateTime(2026, 1, 1, overdueMinute! ~/ 60, overdueMinute! % 60))}',
              ),
              children: [
                if (!widget.premium)
                  Text(
                    strings.t('미완료 재알림은 Pro 기능이에요. 기존 설정은 보관되며 구독 후 다시 적용됩니다.'),
                  ),
                if (widget.premium) ...[
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    itemHeight: null,
                    key: const Key('overdue-interval'),
                    initialValue: overdueDays,
                    decoration: InputDecoration(labelText: strings.t('재알림 간격')),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(strings.t('알리지 않음')),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text(strings.t('매일 한 번 (기본)')),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text(strings.t('2일마다 한 번')),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Text(strings.t('3일마다 한 번')),
                      ),
                      DropdownMenuItem(
                        value: 7,
                        child: Text(strings.t('일주일마다 한 번')),
                      ),
                    ],
                    onChanged: (v) => setState(() => overdueDays = v!),
                  ),
                  if (overdueDays > 0) ...[
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.t('예정 시간과 같게')),
                      value: overdueMinute == null,
                      onChanged: (same) => setState(
                        () => overdueMinute = same
                            ? null
                            : due.hour * 60 + due.minute,
                      ),
                    ),
                    if (overdueMinute != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(
                          strings.t(
                            '재알림 {time}',
                            args: {
                              'time': strings.time(
                                DateTime(
                                  2026,
                                  1,
                                  1,
                                  overdueMinute! ~/ 60,
                                  overdueMinute! % 60,
                                ),
                              ),
                            },
                          ),
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: overdueMinute! ~/ 60,
                              minute: overdueMinute! % 60,
                            ),
                          );
                          if (picked != null && mounted) {
                            setState(
                              () => overdueMinute =
                                  picked.hour * 60 + picked.minute,
                            );
                          }
                        },
                      ),
                    const SizedBox(height: 8),
                    Text(
                      strings.t(
                        overdueDays == 1
                            ? '기한이 지난 뒤 1일 후부터 알려드려요. 완료·건너뛰기·삭제하면 멈춥니다. 미루기를 선택하면 그 시간까지 기다려요.'
                            : '기한이 지난 뒤 {days}일 후부터 알려드려요. 완료·건너뛰기·삭제하면 멈춥니다. 미루기를 선택하면 그 시간까지 기다려요.',
                        args: {'days': overdueDays},
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RepeatUnit>(
              isExpanded: true,
              itemHeight: null,
              initialValue: repeat,
              decoration: InputDecoration(labelText: strings.t('반복')),
              items: RepeatUnit.values
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(
                        strings.t(
                          [
                            '한 번',
                            '매일',
                            '매주 · 요일 선택',
                            '매월 같은 날짜',
                            '매월 특정 번째 요일',
                            '요일 자유 · 주 N회',
                          ][r.index],
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                repeat = v!;
                if (repeat == RepeatUnit.monthlyWeekday &&
                    weekdays.length > 1) {
                  final first = weekdays.toList()..sort();
                  weekdays = {first.first};
                }
              }),
            ),
            if (repeat != RepeatUnit.none) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: interval,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.t(
                    repeat == RepeatUnit.daily
                        ? '반복 간격 (일)'
                        : repeat == RepeatUnit.weekly ||
                              repeat == RepeatUnit.weeklyGoal
                        ? '반복 간격 (주)'
                        : '반복 간격 (개월)',
                  ),
                ),
                validator: (v) =>
                    int.tryParse(v ?? '') == null ||
                        int.parse(v!) < 1 ||
                        int.parse(v) > 365
                    ? strings.t('1~365를 입력해주세요')
                    : null,
              ),
              if (repeat == RepeatUnit.weeklyGoal) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  itemHeight: null,
                  initialValue: countPerWeek,
                  decoration: InputDecoration(labelText: strings.t('일주일 목표')),
                  items: List.generate(
                    7,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                        i == 0
                            ? strings.t('주 1회')
                            : strings.t('주 {count}회', args: {'count': i + 1}),
                      ),
                    ),
                  ),
                  onChanged: (v) => setState(() => countPerWeek = v!),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.t(
                    '요일을 정하지 않고 하루에 한 번 할 수 있어요. 이번 주 목표를 채우면 남은 날의 알림은 쉬고 다음 주에 다시 시작합니다.',
                  ),
                ),
              ],
              if (repeat == RepeatUnit.weekly ||
                  repeat == RepeatUnit.monthlyWeekday) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(
                    7,
                    (i) => FilterChip(
                      label: Text(strings.weekday(i + 1)),
                      selected: weekdays.contains(i + 1),
                      onSelected: (selected) => setState(() {
                        if (repeat == RepeatUnit.monthlyWeekday) {
                          weekdays.clear();
                        }
                        if (selected) {
                          weekdays.add(i + 1);
                        } else {
                          weekdays.remove(i + 1);
                        }
                      }),
                    ),
                  ),
                ),
              ],
              if (repeat == RepeatUnit.monthlyWeekday) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  itemHeight: null,
                  initialValue: monthWeek,
                  decoration: InputDecoration(labelText: strings.t('몇 번째 주')),
                  items: [1, 2, 3, 4, -1]
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == -1 ? strings.t('마지막') : strings.t('$v번째'),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => monthWeek = v!),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => pickDate(true),
                icon: const Icon(Icons.event_available_outlined),
                label: Text(
                  end == null
                      ? strings.t('종료 날짜 없음')
                      : strings.t(
                          '{date}까지',
                          args: {'date': strings.date(end!)},
                        ),
                ),
              ),
              if (end != null)
                TextButton(
                  onPressed: () => setState(() => end = null),
                  child: Text(strings.t('종료 날짜 해제')),
                ),
            ],
            if (widget.task != null && widget.task!.repeat != RepeatUnit.none)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  strings.t('저장하면 이 반복 일정의 예정 회차를 변경합니다. 완료·보류·진행 기록은 유지됩니다.'),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  );
}
