import 'package:flutter/material.dart';

import '../domain/task.dart';

class TaskEditor extends StatefulWidget {
  final Task? task;
  final DateTime initialDate;
  const TaskEditor({super.key, this.task, required this.initialDate});
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController title, note, small, interval;
  late DateTime due;
  DateTime? end;
  int priority = 1, monthWeek = 1, countPerWeek = 1;
  RepeatUnit repeat = RepeatUnit.none;
  String category = '생활';
  Set<int> weekdays = {};
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.task == null ? '할 일 추가' : '반복·할 일 수정')),
    body: Form(
      key: form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: title,
              decoration: const InputDecoration(labelText: '할 일'),
              maxLength: 100,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '제목을 입력해주세요' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: '분류'),
              items: [
                '생활',
                '업무',
                '건강',
                '배움',
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => category = v!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: note,
              decoration: const InputDecoration(labelText: '메모'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: small,
              decoration: const InputDecoration(
                labelText: '작은 첫걸음',
                hintText: '운동복 입고 5분만 움직이기',
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => pickDate(false),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(dayKey(due)),
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
              label: Text(TimeOfDay.fromDateTime(due).format(context)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: priority,
              decoration: const InputDecoration(labelText: '우선순위'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('낮음')),
                DropdownMenuItem(value: 1, child: Text('보통')),
                DropdownMenuItem(value: 2, child: Text('높음')),
              ],
              onChanged: (v) => setState(() => priority = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RepeatUnit>(
              initialValue: repeat,
              decoration: const InputDecoration(labelText: '반복'),
              items: RepeatUnit.values
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(
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
                  labelText:
                      '반복 간격 (${repeat == RepeatUnit.daily
                          ? '일'
                          : repeat == RepeatUnit.weekly || repeat == RepeatUnit.weeklyGoal
                          ? '주'
                          : '개월'})',
                ),
                validator: (v) =>
                    int.tryParse(v ?? '') == null ||
                        int.parse(v!) < 1 ||
                        int.parse(v) > 365
                    ? '1~365를 입력해주세요'
                    : null,
              ),
              if (repeat == RepeatUnit.weeklyGoal) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: countPerWeek,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '일주일 목표'),
                  items: List.generate(
                    7,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text('주 ${i + 1}회'),
                    ),
                  ),
                  onChanged: (v) => setState(() => countPerWeek = v!),
                ),
                const SizedBox(height: 12),
                const Text(
                  '요일을 정하지 않고 하루에 한 번 할 수 있어요. 이번 주 목표를 채우면 남은 날의 알림은 쉬고 다음 주에 다시 시작합니다.',
                ),
              ],
              if (repeat == RepeatUnit.weekly ||
                  repeat == RepeatUnit.monthlyWeekday) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  children: List.generate(
                    7,
                    (i) => FilterChip(
                      label: Text(['월', '화', '수', '목', '금', '토', '일'][i]),
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
                  initialValue: monthWeek,
                  decoration: const InputDecoration(labelText: '몇 번째 주'),
                  items: [1, 2, 3, 4, -1]
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v == -1 ? '마지막' : '$v번째'),
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
                label: Text(end == null ? '종료 날짜 없음' : '${dayKey(end!)}까지'),
              ),
              if (end != null)
                TextButton(
                  onPressed: () => setState(() => end = null),
                  child: const Text('종료 날짜 해제'),
                ),
            ],
            if (widget.task != null && widget.task!.repeat != RepeatUnit.none)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('저장하면 이 반복 일정의 예정 회차를 변경합니다. 완료·보류·진행 기록은 유지됩니다.'),
              ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                if ((repeat == RepeatUnit.weekly ||
                        repeat == RepeatUnit.monthlyWeekday) &&
                    weekdays.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('반복할 요일을 선택해주세요')),
                  );
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
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('저장'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
