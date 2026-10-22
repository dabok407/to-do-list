import 'package:flutter_test/flutter_test.dart';
import 'package:hangeoreum/domain/task.dart';
import 'package:hangeoreum/domain/task_list_sections.dart';

Occurrence _occurrence(
  String id,
  DateTime due, {
  int priority = 1,
  TaskStatus status = TaskStatus.pending,
  DateTime? completed,
  DateTime? reminder,
}) => Occurrence(
  id: id,
  task: Task(
    id: 'task-$id',
    title: id,
    due: due,
    created: DateTime(2026, 1, 1),
    priority: priority,
  ),
  originalDue: due,
  reminder: reminder ?? due,
  status: status,
  completed: completed,
);

List<String> _ids(Iterable<TaskListSection> sections) => [
  for (final section in sections)
    for (final item in section.items) item.id,
];

void main() {
  final now = DateTime(2026, 10, 21, 12);

  test('empty and irrelevant status inputs produce no sections', () {
    expect(taskListSections([], now: now, completed: false), isEmpty);
    expect(taskListSections([], now: now, completed: true), isEmpty);
    final rows = [
      _occurrence('pending', now),
      _occurrence('skipped', now, status: TaskStatus.skipped),
      _occurrence('done', now, status: TaskStatus.completed, completed: now),
    ];
    expect(_ids(taskListSections(rows, now: now, completed: false)), [
      'pending',
    ]);
    expect(_ids(taskListSections(rows, now: now, completed: true)), ['done']);
  });

  test('upcoming groups progressing, overdue dates, then scheduled dates', () {
    final rows = [
      _occurrence('tomorrow', DateTime(2026, 10, 22, 9)),
      _occurrence('older', DateTime(2026, 10, 19, 20)),
      _occurrence('exact-now', now),
      _occurrence(
        'progress-future',
        DateTime(2026, 10, 23, 9),
        status: TaskStatus.progressing,
      ),
      _occurrence('earlier-today', DateTime(2026, 10, 21, 9)),
      _occurrence('yesterday', DateTime(2026, 10, 20, 10)),
      _occurrence(
        'progress-old',
        DateTime(2026, 10, 18, 9),
        status: TaskStatus.progressing,
      ),
      _occurrence(
        'paused',
        DateTime(2026, 10, 20, 11),
        status: TaskStatus.paused,
        reminder: DateTime(2026, 10, 24, 12),
      ),
    ];
    final before = rows.map((item) => item.id).toList();
    final sections = taskListSections(
      rows,
      now: now,
      completed: false,
      order: TaskListOrder.oldest,
    );
    expect(sections.map((s) => s.kind), [
      TaskListSectionKind.progressing,
      TaskListSectionKind.overdue,
      TaskListSectionKind.overdue,
      TaskListSectionKind.overdue,
      TaskListSectionKind.scheduled,
      TaskListSectionKind.scheduled,
    ]);
    expect(sections.map((s) => s.day), [
      null,
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 20),
      DateTime(2026, 10, 21),
      DateTime(2026, 10, 21),
      DateTime(2026, 10, 22),
    ]);
    expect(_ids(sections), [
      'progress-old',
      'progress-future',
      'older',
      'yesterday',
      'paused',
      'earlier-today',
      'exact-now',
      'tomorrow',
    ]);
    expect(_ids(sections).toSet(), before.toSet());
    expect(_ids(sections), hasLength(rows.length));
    expect(rows.map((item) => item.id), before);
    for (final item in sections.expand((s) => s.items)) {
      expect(
        identical(item, rows.firstWhere((row) => row.id == item.id)),
        isTrue,
      );
    }
  });

  test(
    'same-date upcoming rows sort by clock then priority then stable id',
    () {
      final due = DateTime(2026, 10, 21, 16);
      final rows = [
        _occurrence('low', due, priority: 0),
        _occurrence('high-z', due, priority: 2),
        _occurrence('earlier', DateTime(2026, 10, 21, 15), priority: 0),
        _occurrence('normal', due),
        _occurrence('high-a', due, priority: 2),
      ];
      final expected = ['earlier', 'high-a', 'high-z', 'normal', 'low'];
      expect(
        _ids(
          taskListSections(
            rows,
            now: now,
            completed: false,
            order: TaskListOrder.oldest,
          ),
        ),
        expected,
      );
      expect(
        _ids(
          taskListSections(
            rows.reversed,
            now: now,
            completed: false,
            order: TaskListOrder.oldest,
          ),
        ),
        expected,
      );
    },
  );

  test(
    'upcoming defaults to latest dates and clocks within pinned sections',
    () {
      final rows = [
        _occurrence('future-early', DateTime(2026, 10, 22, 9)),
        _occurrence('overdue-old', DateTime(2026, 10, 18, 9)),
        _occurrence('today-late', DateTime(2026, 10, 21, 19)),
        _occurrence('future-late', DateTime(2026, 10, 22, 18)),
        _occurrence('overdue-late', DateTime(2026, 10, 20, 19)),
        _occurrence(
          'progress-old',
          DateTime(2026, 10, 18, 9),
          status: TaskStatus.progressing,
        ),
        _occurrence('overdue-early', DateTime(2026, 10, 20, 8)),
        _occurrence(
          'progress-new',
          DateTime(2026, 10, 24, 9),
          status: TaskStatus.progressing,
        ),
      ];
      final sections = taskListSections(rows, now: now, completed: false);
      expect(sections.map((section) => section.kind), [
        TaskListSectionKind.progressing,
        TaskListSectionKind.overdue,
        TaskListSectionKind.overdue,
        TaskListSectionKind.scheduled,
        TaskListSectionKind.scheduled,
      ]);
      expect(sections.map((section) => section.day), [
        null,
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 22),
        DateTime(2026, 10, 21),
      ]);
      expect(_ids(sections), [
        'progress-new',
        'progress-old',
        'overdue-late',
        'overdue-early',
        'overdue-old',
        'future-late',
        'future-early',
        'today-late',
      ]);
      expect(
        _ids(
          taskListSections(
            rows.reversed,
            now: now,
            completed: false,
            order: TaskListOrder.latest,
          ),
        ),
        _ids(sections),
      );
    },
  );

  test('upcoming clock ties preserve priority and id in either order', () {
    final due = DateTime(2026, 10, 21, 16);
    final rows = [
      _occurrence('low', due, priority: 0),
      _occurrence('high-z', due, priority: 2),
      _occurrence('normal', due),
      _occurrence('high-a', due, priority: 2),
    ];
    for (final order in TaskListOrder.values) {
      expect(
        _ids(taskListSections(rows, now: now, completed: false, order: order)),
        ['high-a', 'high-z', 'normal', 'low'],
        reason: order.name,
      );
    }
  });

  test(
    'completed oldest order uses completion date and time with undated last',
    () {
      final rows = [
        _occurrence(
          'new-early',
          DateTime(2026, 10, 1, 9),
          status: TaskStatus.completed,
          completed: DateTime(2026, 10, 21, 8),
        ),
        _occurrence(
          'legacy',
          DateTime(2026, 9, 1),
          status: TaskStatus.completed,
        ),
        _occurrence(
          'old',
          DateTime(2026, 10, 30, 9),
          status: TaskStatus.completed,
          completed: DateTime(2026, 10, 19, 18),
        ),
        _occurrence(
          'new-late',
          DateTime(2026, 10, 1, 8),
          status: TaskStatus.completed,
          completed: DateTime(2026, 10, 21, 11),
        ),
      ];
      for (final order in TaskListOrder.values) {
        final sections = taskListSections(
          rows,
          now: now,
          completed: true,
          order: order,
        );
        expect(sections.last.kind, TaskListSectionKind.unknownCompletion);
        expect(sections.last.items.single.id, 'legacy');
        expect(
          _ids(sections),
          order == TaskListOrder.oldest
              ? ['old', 'new-early', 'new-late', 'legacy']
              : ['new-late', 'new-early', 'old', 'legacy'],
        );
      }
    },
  );

  test(
    'changing presentation order preserves occurrence identity and input',
    () {
      final rows = [
        _occurrence(
          'snoozed',
          DateTime(2026, 10, 20, 9),
          status: TaskStatus.paused,
          reminder: DateTime(2026, 10, 24, 12),
        ),
        _occurrence('scheduled', DateTime(2026, 10, 22, 9)),
      ];
      final input = List<Occurrence>.of(rows);
      for (final order in TaskListOrder.values) {
        final sections = taskListSections(
          rows,
          now: now,
          completed: false,
          order: order,
        );
        final snoozed = sections
            .expand((section) => section.items)
            .firstWhere((item) => item.id == 'snoozed');
        expect(identical(snoozed, rows.first), isTrue);
        expect(snoozed.originalDue, DateTime(2026, 10, 20, 9));
        expect(snoozed.reminder, DateTime(2026, 10, 24, 12));
        expect(snoozed.status, TaskStatus.paused);
        expect(rows, orderedEquals(input));
      }
    },
  );

  test(
    'completed grouping and clock ordering use actual completion, not due',
    () {
      final rows = [
        _occurrence(
          'older-done',
          DateTime(2026, 10, 30, 9),
          status: TaskStatus.completed,
          completed: DateTime(2026, 10, 19, 18),
        ),
        _occurrence(
          'late-done',
          DateTime(2026, 10, 1, 8),
          status: TaskStatus.completed,
          completed: DateTime(2026, 10, 21, 11),
        ),
        _occurrence(
          'early-done',
          DateTime(2026, 10, 22, 20),
          status: TaskStatus.completed,
          completed: DateTime(2026, 10, 21, 8),
        ),
        _occurrence('undone-stale', now, completed: DateTime(2026, 10, 21, 12)),
        _occurrence('skipped', now, status: TaskStatus.skipped),
      ];
      final sections = taskListSections(rows, now: now, completed: true);
      expect(
        sections.map((s) => s.kind),
        everyElement(TaskListSectionKind.completed),
      );
      expect(sections.map((s) => s.day), [
        DateTime(2026, 10, 21),
        DateTime(2026, 10, 19),
      ]);
      expect(_ids(sections), ['late-done', 'early-done', 'older-done']);
    },
  );

  test('completed ties remain deterministic regardless of input order', () {
    final due = DateTime(2026, 10, 20, 9);
    final done = DateTime(2026, 10, 21, 10);
    final rows = [
      _occurrence('z', due, status: TaskStatus.completed, completed: done),
      _occurrence('a', due, status: TaskStatus.completed, completed: done),
      _occurrence(
        'high',
        due,
        status: TaskStatus.completed,
        priority: 2,
        completed: done,
      ),
    ];
    for (final order in TaskListOrder.values) {
      for (final input in [rows, rows.reversed]) {
        expect(
          _ids(
            taskListSections(input, now: now, completed: true, order: order),
          ),
          ['high', 'a', 'z'],
          reason: order.name,
        );
      }
    }
  });

  test(
    'legacy completions without clock stay intact in an undated last group',
    () {
      final rows = [
        _occurrence(
          'legacy-b',
          DateTime(2026, 9, 20),
          status: TaskStatus.completed,
        ),
        _occurrence(
          'legacy-a',
          DateTime(2026, 9, 10),
          status: TaskStatus.completed,
        ),
        _occurrence(
          'dated',
          DateTime(2026, 1, 1),
          status: TaskStatus.completed,
          completed: DateTime(2026, 2, 1),
        ),
      ];
      final sections = taskListSections(rows, now: now, completed: true);
      expect(sections, hasLength(2));
      expect(sections.last.kind, TaskListSectionKind.unknownCompletion);
      expect(sections.last.day, isNull);
      expect(sections.last.id, 'unknownCompletion');
      expect(_ids(sections).toSet(), rows.map((row) => row.id).toSet());
      expect(_ids(sections), hasLength(rows.length));
      expect(sections.last.items.every((row) => row.completed == null), isTrue);
    },
  );

  test(
    'UTC and local timestamps for one instant share local calendar groups',
    () {
      final dueUtc = DateTime.utc(2026, 10, 21, 23, 30);
      final doneUtc = DateTime.utc(2026, 10, 22, 0, 15);
      final localDue = dueUtc.toLocal();
      final localDone = doneUtc.toLocal();
      final scheduled = taskListSections(
        [_occurrence('utc', dueUtc), _occurrence('local', localDue)],
        now: dueUtc.subtract(const Duration(hours: 1)),
        completed: false,
      );
      expect(scheduled, hasLength(1));
      expect(scheduled.single.day, dayOf(localDue));
      final done = taskListSections(
        [
          _occurrence(
            'utc',
            dueUtc,
            status: TaskStatus.completed,
            completed: doneUtc,
          ),
          _occurrence(
            'local',
            localDue,
            status: TaskStatus.completed,
            completed: localDone,
          ),
        ],
        now: doneUtc.add(const Duration(hours: 1)),
        completed: true,
      );
      expect(done, hasLength(1));
      expect(done.single.day, dayOf(localDone));
      expect(_ids(done), ['local', 'utc']);
    },
  );
}
