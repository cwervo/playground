import 'package:flutter/material.dart';

/// Tiny bar sparkline used for requests-per-second over the last minute.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color, this.height = 28});

  final List<int> values;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(values, c),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<int>(0, (a, b) => a > b ? a : b);
    final n = values.length;
    final slot = size.width / n;
    final barW = (slot * 0.7).clamp(1.0, 12.0);
    final base = Paint()..color = color.withValues(alpha: 0.15);
    final fill = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final x = i * slot + (slot - barW) / 2;
      canvas.drawRect(Rect.fromLTWH(x, size.height - 1, barW, 1), base);
      if (maxV == 0 || values[i] == 0) continue;
      final h = (values[i] / maxV) * (size.height - 2) + 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - h, barW, h), const Radius.circular(1)),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}
