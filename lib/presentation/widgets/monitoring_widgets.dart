import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/services/frame_analyzer_service.dart';

/// Rule-of-thirds grid overlay
class GridOverlay extends StatelessWidget {
  const GridOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GridPainter(),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1;

    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Center crosshair
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx - 8, cy), Offset(cx + 8, cy), paint);
    canvas.drawLine(Offset(cx, cy - 8), Offset(cx, cy + 8), paint);
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// Horizon level indicator driven by the accelerometer
class LevelIndicator extends StatelessWidget {
  final double rollDegrees;

  const LevelIndicator({super.key, required this.rollDegrees});

  @override
  Widget build(BuildContext context) {
    final isLevel = rollDegrees.abs() < 1.5;
    final color = isLevel ? Colors.tealAccent : Colors.white70;

    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              height: 48,
              child: CustomPaint(
                painter: _LevelPainter(
                  rollDegrees: rollDegrees,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isLevel ? 'LEVEL' : '${rollDegrees.toStringAsFixed(0)}°',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  final double rollDegrees;
  final Color color;

  _LevelPainter({required this.rollDegrees, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Fixed side markers
    final markerPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx - 60, center.dy - 14),
        Offset(center.dx - 60, center.dy - 8), markerPaint);
    canvas.drawLine(Offset(center.dx + 60, center.dy - 14),
        Offset(center.dx + 60, center.dy - 8), markerPaint);

    // Rotating horizon line
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rollDegrees * math.pi / 180);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-46, 0), const Offset(46, 0), linePaint);
    canvas.drawCircle(Offset.zero, 3, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LevelPainter old) => old.rollDegrees != rollDegrees;
}

/// Luminance histogram drawn from live frame statistics
class HistogramWidget extends StatelessWidget {
  final FrameStats? stats;

  const HistogramWidget({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats == null || stats!.histogram.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Container(
        width: 140,
        height: 64,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: CustomPaint(
          painter: _HistogramPainter(histogram: stats!.histogram),
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> histogram;

  _HistogramPainter({required this.histogram});

  @override
  void paint(Canvas canvas, Size size) {
    final maxCount =
        histogram.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30).toDouble();
    final binWidth = size.width / histogram.length;

    for (var i = 0; i < histogram.length; i++) {
      final h = (histogram[i] / maxCount) * size.height;
      final luma = i / (histogram.length - 1);
      final paint = Paint()
        ..color = Color.lerp(Colors.tealAccent, Colors.white, luma)!
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(i * binWidth, size.height - h, binWidth - 0.5, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HistogramPainter old) => true;
}

/// Zebra stripes shown over the preview while highlights are clipped.
/// The overlay is global (the plugin gives no per-pixel access), with
/// opacity driven by the real measured highlight ratio.
class ZebraOverlay extends StatelessWidget {
  final double highlightRatio;

  const ZebraOverlay({super.key, required this.highlightRatio});

  @override
  Widget build(BuildContext context) {
    if (highlightRatio < 0.005) return const SizedBox.shrink();

    final opacity = (highlightRatio * 6).clamp(0.08, 0.6).toDouble();

    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          size: Size.infinite,
          painter: _ZebraPainter(),
        ),
      ),
    );
  }
}

class _ZebraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amber
      ..strokeWidth = 7;

    const step = 14.0;
    for (var d = -size.height; d < size.width + size.height; d += step * 2) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_ZebraPainter old) => false;
}

/// Highlight + shadow warning readout, driven by real frame statistics
class ExposureMeterWidget extends StatelessWidget {
  final FrameStats? stats;

  const ExposureMeterWidget({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    if (s == null || s.sampledPixels == 0) return const SizedBox.shrink();

    final ev = s.estimatedEv;
    final clipped = s.highlightRatio > 0.02;

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              clipped ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: clipped ? Colors.amber : Colors.tealAccent,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              'EV ${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(1)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (clipped) ...[
              const SizedBox(width: 8),
              Text(
                '${(s.highlightRatio * 100).toStringAsFixed(0)}% CLIP',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
