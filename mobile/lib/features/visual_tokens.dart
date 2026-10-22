import 'package:flutter/material.dart';

/// Shared display colors and category identity for the app and statistics.
abstract final class TaskVisuals {
  static const ink = Color(0xff252c32);
  static const muted = Color(0xff69717a);
  static const blue = Color(0xff466c82);
  static const red = Color(0xffa9493e);
  static const line = Color(0xffe6e7e8);
  static const quietSurface = Color(0xfff4f5f5);
  static const categoryColors = {
    '생활': Color(0xffad5618),
    '업무': Color(0xff315dca),
    '건강': Color(0xff267447),
    '배움': Color(0xff7546ba),
    '기타': Color(0xff59636f),
  };

  static Color categoryInk(String category) =>
      categoryColors[switch (category) {
        '운동' => '건강',
        '공부' => '배움',
        _ => category,
      }] ??
      categoryColors['기타']!;

  static Color priorityInk(int priority) => switch (priority) {
    2 => red,
    0 => const Color(0xff626b73),
    _ => blue,
  };

  static IconData categoryIcon(String category) => switch (category) {
    '생활' => Icons.home_outlined,
    '업무' => Icons.work_outline_rounded,
    '건강' || '운동' => Icons.favorite_border_rounded,
    '배움' || '공부' => Icons.auto_stories_outlined,
    _ => Icons.more_horiz_rounded,
  };
}

/// One category identity for task metadata, calendar headings and chart rows.
/// The icon is decorative: the visible label also identifies the category.
class CategoryLabel extends StatelessWidget {
  final String category, label;
  const CategoryLabel({super.key, required this.category, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: Icon(
          TaskVisuals.categoryIcon(category),
          color: TaskVisuals.categoryInk(category),
          size: 16,
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: TaskVisuals.ink,
          ),
        ),
      ),
    ],
  );
}
