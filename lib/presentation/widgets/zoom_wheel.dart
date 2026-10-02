import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../providers/camera_provider.dart';

/// Professional continuous zoom wheel with detent stops.
///
/// - Drag horizontally for smooth continuous zoom (logarithmic)
/// - Tap a detent label to jump to it
/// - Double-tap for a quick return to 1x
class ZoomWheel extends StatefulWidget {
  final CameraProvider cameraProvider;

  const ZoomWheel({super.key, required this.cameraProvider});

  @override
  State<ZoomWheel> createState() => _ZoomWheelState();
}

class _ZoomWheelState extends State<ZoomWheel> {
  double? _dragStartFactor;
  double? _dragStartX;

  static const _doubleFactorPerPx = 140.0; // px of drag per doubling

  @override
  Widget build(BuildContext context) {
    final provider = widget.cameraProvider;
    final detents = provider.zoomDetents;
    final min = provider.minZoomFactor;
    final max = math.max(provider.maxZoomFactor, min);
    final current = provider.zoomFactor.clamp(min, max);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: (_) => _dragStartFactor = null,
          onTapUp: (details) => _onTap(details.localPosition.dx, min, max),
          onDoubleTap: () => provider.resetZoom(),
          child: SizedBox(
            width: 260,
            height: 40,
            child: CustomPaint(
              painter: _ZoomWheelPainter(
                min: min,
                max: max,
                current: current,
                detents: detents,
              ),
            ),
          ),
        ),
        Text(
          '${current.toStringAsFixed(1)}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartFactor = widget.cameraProvider.zoomFactor;
    _dragStartX = details.globalPosition.dx;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final startFactor = _dragStartFactor;
    final startX = _dragStartX;
    if (startFactor == null || startX == null) return;

    final dx = details.globalPosition.dx - startX;
    final factor = startFactor * math.pow(2, dx / _doubleFactorPerPx);
    widget.cameraProvider.setZoomFactor(factor.toDouble());
  }

  void _onTap(double localX, double min, double max) {
    final provider = widget.cameraProvider;
    // Nearest detent to the tap position (log space)
    double best = min;
    var bestDist = double.infinity;
    for (final d in provider.zoomDetents) {
      final pos = _logPos(d, min, max) * 260;
      final dist = (pos - localX).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = d;
      }
    }
    provider.setZoomFactor(best);
  }

  double _logPos(double v, double min, double max) {
    final lo = math.log(min);
    final hi = math.log(max);
    if (hi == lo) return 0;
    return ((math.log(v.clamp(min, max)) - lo) / (hi - lo)).clamp(0.0, 1.0);
  }
}

class _ZoomWheelPainter extends CustomPainter {
  final double min;
  final double max;
  final double current;
  final List<double> detents;

  _ZoomWheelPainter({
    required this.min,
    required this.max,
    required this.current,
    required this.detents,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Track
    canvas.drawLine(
      Offset(8, centerY),
      Offset(size.width - 8, centerY),
      trackPaint,
    );

    // Detent ticks + labels
    for (final d in detents) {
      final pos = _logPos(d) * (size.width - 16) + 8;
      final isCurrent = (d - current).abs() < 0.05;
      final tickPaint = Paint()
        ..color = isCurrent ? Colors.tealAccent : Colors.white70
        ..strokeWidth = isCurrent ? 3 : 2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(pos, centerY - (isCurrent ? 9 : 6)),
        Offset(pos, centerY + (isCurrent ? 9 : 6)),
        tickPaint,
      );

      _drawLabel(canvas, _format(d), pos, centerY + 16, isCurrent);
    }

    // Thumb
    final thumbPos = _logPos(current) * (size.width - 16) + 8;
    final thumbPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(thumbPos, centerY), 5, thumbPaint);
    canvas.drawCircle(
      Offset(thumbPos, centerY),
      8,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  String _format(double v) =>
      v == v.roundToDouble() ? '${v.round()}x' : '${v.toStringAsFixed(1)}x';

  void _drawLabel(
    Canvas canvas,
    String text,
    double x,
    double y,
    bool highlighted,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: highlighted ? Colors.tealAccent : Colors.white60,
          fontSize: 10,
          fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  double _logPos(double v) {
    final lo = math.log(min);
    final hi = math.log(max);
    if (hi == lo) return 0;
    return ((math.log(v.clamp(min, max)) - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_ZoomWheelPainter old) =>
      old.current != current || old.min != min || old.max != max;
}
