import 'package:flutter/material.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [
                  FontFeature.tabularFigures(),
                ])),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Human-friendly formatting helpers shared by the screens.
String fmtInt(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String fmtBytes(int v) {
  if (v < 1024) return '$v B';
  if (v < 1024 * 1024) return '${(v / 1024).toStringAsFixed(v % 1024 == 0 ? 0 : 1)} KiB';
  return '${(v / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

String fmtDuration(int ms) {
  final s = ms ~/ 1000;
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
  if (s < 86400) return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
  return '${s ~/ 86400}d ${(s % 86400) ~/ 3600}h';
}

String fmtMicros(double us) {
  if (us < 1000) return '${us.toStringAsFixed(us < 10 ? 1 : 0)} µs';
  return '${(us / 1000).toStringAsFixed(2)} ms';
}

String fmtAgo(int epochMs) {
  if (epochMs == 0) return 'never';
  final d = DateTime.now().millisecondsSinceEpoch - epochMs;
  if (d < 2000) return 'just now';
  if (d < 60000) return '${d ~/ 1000}s ago';
  if (d < 3600000) return '${d ~/ 60000}m ago';
  return '${d ~/ 3600000}h ago';
}

String fmtClock(int epochMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
