import 'package:flutter/material.dart';

const settingsInk = Color(0xff292e2b);
const settingsMuted = Color(0xff707773);

class SettingsIcon extends StatelessWidget {
  final IconData icon;
  const SettingsIcon(this.icon, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: const Color(0xfff1f3f1),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, size: 19, color: const Color(0xff535e57)),
  );
}

class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const SettingsGroup({super.key, this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text(
            title!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: settingsMuted,
            ),
          ),
        ),
      Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe2e6e2)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 58,
                  color: Color(0xffecefec),
                ),
              children[i],
            ],
          ],
        ),
      ),
    ],
  );
}

class SettingsMenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle, value;
  final VoidCallback? onTap;
  const SettingsMenuRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stackedValue =
          constraints.maxWidth < 320 ||
          MediaQuery.textScalerOf(context).scale(14) > 19;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              SettingsIcon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: settingsInk,
                      ),
                    ),
                    if (subtitle != null ||
                        (value != null && stackedValue)) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle ?? value!,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: settingsMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null && !stackedValue) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .42,
                  ),
                  child: Text(
                    value!,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 13, color: settingsMuted),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xff929a94),
              ),
            ],
          ),
        ),
      );
    },
  );
}
