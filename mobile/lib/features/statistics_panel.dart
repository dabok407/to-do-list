import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/statistics_breakdown.dart';
import '../domain/task.dart';
import '../l10n/app_strings.dart';
import 'visual_tokens.dart';

const _ink = TaskVisuals.ink;
const _muted = TaskVisuals.muted;
const _line = TaskVisuals.line;
const _heading = TextStyle(
  color: _ink,
  fontSize: 17,
  fontWeight: FontWeight.w600,
  height: 1.35,
);
const _support = TextStyle(color: _muted, fontSize: 12, height: 1.5);

String _categoryShare(int count, int total) {
  if (total == 0) return '—';
  final percent = (count / total * 100).toStringAsFixed(1);
  return '${percent.endsWith('.0') ? percent.substring(0, percent.length - 2) : percent}%';
}

/// Access is controlled by the host. Summary and charts share one occurrence
/// breakdown; event-based snooze statistics still come from the repository.
class StatisticsPanel extends StatefulWidget {
  final List<Occurrence> items;
  final Map<String, Object> statistics;
  final DateTime? now;
  final Future<Map<String, Object>> Function(DateTime from, DateTime until)?
  loadStatistics;
  const StatisticsPanel({
    super.key,
    required this.items,
    required this.statistics,
    this.now,
    this.loadStatistics,
  });
  @override
  State<StatisticsPanel> createState() => _StatisticsPanelState();
}

class _StatisticsPanelState extends State<StatisticsPanel> {
  bool categoryView = false;
  String? selectedCategory;
  DateTimeRange? selectedRange;
  DateTime? queriedFrom, queriedUntil;
  Map<String, Object>? queriedStatistics;
  bool loading = false, queryFailed = false, pickerOpen = false;
  int requestToken = 0;

  DateTime get clock => widget.now ?? DateTime.now();

  (DateTime, DateTime) bounds(DateTimeRange? range, DateTime now) {
    if (range == null) return (now.subtract(const Duration(days: 30)), now);
    final from = dayOf(range.start);
    final afterEnd = DateTime(
      range.end.year,
      range.end.month,
      range.end.day + 1,
    );
    final end = afterEnd.subtract(const Duration(microseconds: 1));
    return (from, end.isAfter(now) ? now : end);
  }

  @override
  void didUpdateWidget(covariant StatisticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        !identical(oldWidget.items, widget.items) ||
        !identical(oldWidget.statistics, widget.statistics) ||
        oldWidget.now != widget.now ||
        oldWidget.loadStatistics != widget.loadStatistics;
    if (!changed) return;
    if (selectedRange != null || loading || queryFailed) {
      query(selectedRange);
    } else {
      queriedStatistics = null;
      queriedFrom = null;
      queriedUntil = null;
    }
  }

  @override
  void dispose() {
    requestToken++;
    super.dispose();
  }

  Future<void> query(DateTimeRange? range) async {
    final token = ++requestToken;
    final (from, until) = bounds(range, clock);
    setState(() {
      selectedRange = range;
      queriedFrom = from;
      queriedUntil = until;
      queriedStatistics = null;
      selectedCategory = null;
      loading = true;
      queryFailed = false;
    });
    try {
      final loader = widget.loadStatistics;
      final result = loader == null
          ? widget.statistics
          : await loader(from, until);
      if (!mounted || token != requestToken) return;
      setState(() {
        queriedStatistics = Map<String, Object>.unmodifiable(result);
        loading = false;
      });
    } catch (_) {
      if (!mounted || token != requestToken) return;
      setState(() {
        loading = false;
        queryFailed = true;
      });
    }
  }

  Future<void> choosePeriod() async {
    if (pickerOpen) return;
    final strings = AppStrings.of(context);
    final now = clock;
    final initial =
        selectedRange ??
        DateTimeRange(
          start: dayOf(now.subtract(const Duration(days: 30))),
          end: dayOf(now),
        );
    setState(() => pickerOpen = true);
    DateTimeRange? picked;
    try {
      picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: dayOf(now),
        currentDate: now,
        initialDateRange: initial,
        helpText: strings.t('통계 조회 기간'),
        confirmText: strings.t('조회'),
        saveText: strings.t('조회'),
      );
    } finally {
      if (mounted) setState(() => pickerOpen = false);
    }
    if (!mounted || picked == null) return;
    await query(picked);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final now = clock;
    final (defaultFrom, defaultUntil) = bounds(selectedRange, now);
    final from = queriedFrom ?? defaultFrom;
    final until = queriedUntil ?? defaultUntil;
    final statistics = queriedStatistics ?? widget.statistics;
    final data = StatisticsBreakdown.fromOccurrences(
      widget.items,
      now: now,
      from: from,
      until: until,
    );
    final rate = data.total == 0
        ? '—'
        : '${(data.completed / data.total * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _PeriodHeader(
          strings: strings,
          canReset: selectedRange != null,
          onReset: () => query(null),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('statistics-period-select'),
          onPressed: pickerOpen ? null : choosePeriod,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(0, 56),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            foregroundColor: _ink,
            textStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 14),
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.date_range_outlined, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${strings.date(from)} – ${strings.date(until)}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: _ink,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 19),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (loading)
          Semantics(
            key: const Key('statistics-period-loading'),
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: TaskVisuals.blue,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Flexible(
                    child: Text(strings.t('통계를 불러오는 중이에요.'), style: _support),
                  ),
                ],
              ),
            ),
          )
        else if (queryFailed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.t('통계를 불러오지 못했어요. 다시 조회해주세요.'), style: _support),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('statistics-period-retry'),
                  onPressed: () => query(selectedRange),
                  style: OutlinedButton.styleFrom(
                    textStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                    ),
                  ),
                  child: Text(strings.t('다시 조회')),
                ),
              ],
            ),
          )
        else ...[
          _ViewTabs(
            categoryView: categoryView,
            strings: strings,
            onChanged: (value) => setState(() => categoryView = value),
          ),
          const SizedBox(height: 15),
          Semantics(
            key: const Key('statistics-summary'),
            label: strings.t(
              '완료율 {rate}, 집계한 회차 {total}개 중 {done}개 완료',
              args: {'rate': rate, 'total': data.total, 'done': data.completed},
            ),
            child: ExcludeSemantics(
              child: Text(
                strings.t(
                  '집계 {total}회 중 {done}회 완료 · {rate}',
                  args: {
                    'total': data.total,
                    'done': data.completed,
                    'rate': rate,
                  },
                ),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: _ink,
                  fontSize: 14,
                  height: 1.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          if (categoryView)
            _CategoryDonut(
              data: data,
              strings: strings,
              selected: data.categoryCompleted.containsKey(selectedCategory)
                  ? selectedCategory
                  : null,
              onSelect: (name) => setState(
                () => selectedCategory = name == selectedCategory ? null : name,
              ),
            )
          else
            _PriorityRings(data: data, strings: strings),
          const SizedBox(height: 24),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 23),
          Text(strings.t('세부 기록'), style: _heading),
          const SizedBox(height: 12),
          _DetailRow(
            field: '등록한 할 일',
            label: strings.t('등록한 할 일'),
            value: strings.t(
              '{n}개',
              args: {'n': statistics['registered'] ?? 0},
            ),
          ),
          _DetailRow(
            field: '미룬 횟수',
            label: strings.t('미룬 횟수'),
            value: strings.t('{n}회', args: {'n': statistics['snoozes'] ?? 0}),
          ),
          _DetailRow(
            field: '평균 미룬 시간',
            label: strings.t('평균 미룬 시간'),
            value: strings.t(
              '{n}분',
              args: {'n': ((statistics['average'] as num?) ?? 0).round()},
            ),
          ),
          _DetailRow(
            field: '자주 완료한 시간대',
            label: strings.t('자주 완료한 시간대'),
            value: _hour(strings, statistics['hour']),
          ),
          const SizedBox(height: 18),
          Text(
            strings.t(
              '분류별 비중은 조회 기간에 완료한 회차를 기준으로 계산합니다. 우선순위별 완료율은 해당 기간에 예정 시간이 지났거나 미리 완료한 회차를 대상으로 계산합니다.',
            ),
            style: _support,
          ),
          const SizedBox(height: 8),
          Text(
            strings.t('반복 일정은 각 회차를 별도로 집계합니다. 자동으로 건너뛴 주간 목표 회차는 대상에서 제외합니다.'),
            style: _support,
          ),
        ],
      ],
    );
  }

  String _hour(AppStrings strings, Object? value) {
    if (value == null || value == '기록 없음') return strings.t('기록 없음');
    final hour = int.tryParse(value.toString().replaceAll('시', ''));
    return !strings.isEnglish || hour == null
        ? value.toString()
        : strings.time(DateTime(2000, 1, 1, hour));
  }
}

class _PeriodHeader extends StatelessWidget {
  final AppStrings strings;
  final bool canReset;
  final VoidCallback onReset;
  const _PeriodHeader({
    required this.strings,
    required this.canReset,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontFamily: 'Pretendard',
      color: _ink,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    const buttonStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 13,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    final label = Text(strings.t('조회 기간'), style: labelStyle);
    final button = OutlinedButton.icon(
      key: const Key('statistics-period-reset'),
      onPressed: canReset ? onReset : null,
      icon: const Icon(Icons.refresh_rounded, size: 17),
      label: Text(strings.t('최근 30일')),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: _ink,
        backgroundColor: TaskVisuals.quietSurface,
        disabledForegroundColor: const Color(0xff9198a0),
        disabledBackgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xffcbd0d4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: buttonStyle,
      ),
    );
    double textWidth(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final neededWidth =
        textWidth(strings.t('조회 기간'), labelStyle) +
        textWidth(strings.t('최근 30일'), buttonStyle) +
        17 +
        8 +
        24 +
        16;
    return LayoutBuilder(
      builder: (context, constraints) => neededWidth <= constraints.maxWidth
          ? Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 16),
                button,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 7),
                Align(alignment: Alignment.centerRight, child: button),
              ],
            ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  final bool categoryView;
  final AppStrings strings;
  final ValueChanged<bool> onChanged;
  const _ViewTabs({
    required this.categoryView,
    required this.strings,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: TaskVisuals.quietSurface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        for (final category in [false, true])
          Expanded(
            child: Semantics(
              key: Key(
                category
                    ? 'statistics-tab-category'
                    : 'statistics-tab-priority',
              ),
              label: strings.t(category ? '분류별' : '우선순위별'),
              selected: categoryView == category,
              button: true,
              onTap: () => onChanged(category),
              child: ExcludeSemantics(
                child: TextButton(
                  onPressed: () => onChanged(category),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    foregroundColor: categoryView == category ? _ink : _muted,
                    backgroundColor: categoryView == category
                        ? Colors.white
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    textStyle: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: categoryView == category
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  child: Text(
                    strings.t(category ? '분류별' : '우선순위별'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _PriorityRings extends StatelessWidget {
  final StatisticsBreakdown data;
  final AppStrings strings;
  const _PriorityRings({required this.data, required this.strings});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(strings.t('완료 / 집계 대상'), textAlign: TextAlign.end, style: _support),
      const SizedBox(height: 15),
      LayoutBuilder(
        builder: (context, constraints) {
          final stacked = MediaQuery.textScalerOf(context).scale(14) > 19;
          final children = [
            for (final priority in [2, 1, 0])
              _PriorityMetric(
                priority: priority,
                count: data.priorities[priority]!,
                strings: strings,
                horizontal: stacked,
              ),
          ];
          return stacked
              ? Column(
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: 24),
                      children[i],
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Expanded(child: children[i]),
                    ],
                  ],
                );
        },
      ),
    ],
  );
}

class _PriorityMetric extends StatelessWidget {
  final int priority;
  final StatisticsCount count;
  final AppStrings strings;
  final bool horizontal;
  const _PriorityMetric({
    required this.priority,
    required this.count,
    required this.strings,
    required this.horizontal,
  });
  @override
  Widget build(BuildContext context) {
    final name = strings.t(switch (priority) {
      2 => '높음',
      0 => '낮음',
      _ => '보통',
    });
    final percent = count.rate == null
        ? '—'
        : '${(count.rate! * 100).round()}%';
    final color = TaskVisuals.priorityInk(priority);
    final ring = AspectRatio(
      aspectRatio: 1,
      child: Semantics(
        label: strings.t(
          '{name}, {done} / {total}, 완료율 {rate}',
          args: {
            'name': name,
            'done': count.completed,
            'total': count.total,
            'rate': percent,
          },
        ),
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: _ProgressRingPainter(value: count.rate ?? 0, color: color),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    percent,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final caption = Column(
      crossAxisAlignment: horizontal
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          name,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${count.completed} / ${count.total}',
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    return Container(
      key: ValueKey('stats-priority-$priority'),
      child: horizontal
          ? Row(
              children: [
                SizedBox(width: 104, height: 104, child: ring),
                const SizedBox(width: 22),
                Expanded(child: caption),
              ],
            )
          : Column(children: [ring, const SizedBox(height: 14), caption]),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double value;
  final Color color;
  const _ProgressRingPainter({required this.value, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final width = (size.shortestSide * .085).clamp(7.0, 10.0).toDouble();
    final rect = Rect.fromLTWH(
      width / 2,
      width / 2,
      size.width - width,
      size.height - width,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = _line;
    canvas.drawOval(rect, paint);
    if (value > 0) {
      paint.color = color;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value.clamp(0, 1),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

class _CategoryDonut extends StatelessWidget {
  final StatisticsBreakdown data;
  final AppStrings strings;
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _CategoryDonut({
    required this.data,
    required this.strings,
    required this.selected,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    final entries = data.categoryCompleted.entries.toList();
    final count = selected == null
        ? data.completed
        : data.categoryCompleted[selected] ?? 0;
    final label = selected == null
        ? strings.t('전체 완료')
        : strings.category(selected!);
    final share = _categoryShare(count, data.completed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final largeType = MediaQuery.textScalerOf(context).scale(14) > 19;
            final diameter = math.min(
              constraints.maxWidth,
              largeType ? 268.0 : 196.0,
            );
            final stroke = largeType ? 25.0 : 23.0;
            return Center(
              child: SizedBox.square(
                dimension: diameter,
                child: GestureDetector(
                  key: const Key('statistics-category-donut'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final delta =
                        details.localPosition -
                        Offset(diameter / 2, diameter / 2);
                    final radius = diameter / 2 - stroke / 2;
                    if (delta.distance < radius - stroke / 2 - 8 ||
                        delta.distance > radius + stroke / 2 + 8) {
                      return;
                    }
                    final angle =
                        (math.atan2(delta.dy, delta.dx) +
                            math.pi / 2 +
                            math.pi * 2) %
                        (math.pi * 2);
                    var cursor = 0.0;
                    for (final entry in entries) {
                      final sweep = data.completed == 0
                          ? 0.0
                          : entry.value / data.completed * math.pi * 2;
                      if (sweep > 0 &&
                          angle >= cursor &&
                          angle < cursor + sweep) {
                        onSelect(entry.key);
                        return;
                      }
                      cursor += sweep;
                    }
                  },
                  child: CustomPaint(
                    painter: _DonutPainter(
                      entries: entries,
                      total: data.completed,
                      selected: selected,
                      stroke: stroke,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(stroke + 18),
                      child: Semantics(
                        key: const Key('statistics-category-summary'),
                        liveRegion: true,
                        label: strings.t(
                          '{name}, {n}개 완료, 비중 {share}',
                          args: {'name': label, 'n': count, 'share': share},
                        ),
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '$count',
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 34,
                                      height: 1.1,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                share,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          strings.t('완료한 전체 {n}개 기준', args: {'n': data.completed}),
          textAlign: TextAlign.center,
          style: _support,
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: _RecordColumns(
            label: Text(strings.t('분류'), style: _support),
            value: _CategoryValues(
              count: strings.t('완료 수'),
              share: strings.t('비중'),
              countKey: const Key('stats-category-count-heading'),
              shareKey: const Key('stats-category-share-heading'),
              style: _support,
            ),
          ),
        ),
        for (final entry in entries)
          _CategoryRow(
            name: entry.key,
            label: strings.category(entry.key),
            count: entry.value,
            total: data.completed,
            selected: selected == entry.key,
            strings: strings,
            onTap: () => onSelect(entry.key),
          ),
        if (data.completed == 0) ...[
          const SizedBox(height: 12),
          Text(strings.t('조회 기간에는 완료한 기록이 없어요.'), style: _support),
        ],
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final int total;
  final String? selected;
  final double stroke;
  const _DonutPainter({
    required this.entries,
    required this.total,
    required this.selected,
    required this.stroke,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = _line;
    canvas.drawOval(rect, paint);
    if (total == 0) return;
    var cursor = -math.pi / 2;
    for (final entry in entries) {
      if (entry.value == 0) continue;
      final sweep = entry.value / total * math.pi * 2;
      final gap = math.min(.025, sweep * .15);
      paint.color = TaskVisuals.categoryInk(
        entry.key,
      ).withValues(alpha: selected == null || selected == entry.key ? 1 : .38);
      canvas.drawArc(rect, cursor + gap / 2, sweep - gap, false, paint);
      cursor += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _CategoryRow extends StatelessWidget {
  final String name, label;
  final int count, total;
  final bool selected;
  final AppStrings strings;
  final VoidCallback onTap;
  const _CategoryRow({
    required this.name,
    required this.label,
    required this.count,
    required this.total,
    required this.selected,
    required this.strings,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final share = _categoryShare(count, total);
    return Semantics(
      key: ValueKey('stats-category-$name'),
      selected: selected,
      button: true,
      label: strings.t(
        '{name}, {n}개 완료, 비중 {share}',
        args: {'name': label, 'n': count, 'share': share},
      ),
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? TaskVisuals.quietSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: _RecordColumns(
              label: CategoryLabel(category: name, label: label),
              value: _CategoryValues(
                count: '$count',
                share: share,
                countKey: ValueKey('stats-category-count-$name'),
                shareKey: ValueKey('stats-category-share-$name'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String field, label, value;
  const _DetailRow({
    required this.field,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
    child: _RecordColumns(
      label: Text(
        label,
        key: ValueKey('stats-detail-label-$field'),
        style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
      ),
      value: Text(
        value,
        key: ValueKey('stats-detail-value-$field'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _ink,
          fontSize: 13,
          height: 1.45,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

/// Shared edges and responsive behavior for both statistics record tables.
class _RecordColumns extends StatelessWidget {
  final Widget label, value;
  const _RecordColumns({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (MediaQuery.textScalerOf(context).scale(13) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            const SizedBox(height: 8),
            Align(alignment: Alignment.center, child: value),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 5, child: label),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Align(alignment: Alignment.center, child: value),
          ),
        ],
      );
    },
  );
}

class _CategoryValues extends StatelessWidget {
  final String count, share;
  final Key countKey, shareKey;
  final TextStyle? style;
  const _CategoryValues({
    required this.count,
    required this.share,
    required this.countKey,
    required this.shareKey,
    this.style,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          count,
          key: countKey,
          textAlign: TextAlign.center,
          style: style ?? _number,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          share,
          key: shareKey,
          textAlign: TextAlign.center,
          style: style ?? _number,
        ),
      ),
    ],
  );
  static const _number = TextStyle(
    color: _ink,
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
