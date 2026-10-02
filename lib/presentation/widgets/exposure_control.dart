import 'package:flutter/material.dart';
import '../providers/camera_provider.dart';

/// Focus reticle drawn at the tapped preview point, with an AF-lock badge.
class FocusReticle extends StatelessWidget {
  final CameraProvider cameraProvider;

  const FocusReticle({super.key, required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    final point = cameraProvider.focusPoint;
    if (point == null || !cameraProvider.showReticle) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final x = (point.dx.clamp(0.05, 0.95)) * constraints.maxWidth;
        final y = (point.dy.clamp(0.05, 0.95)) * constraints.maxHeight;

        return Stack(
          children: [
            Positioned(
              left: x - 44,
              top: y - 44,
              child: _ReticlePainterWidget(locked: cameraProvider.focusLocked),
            ),
            if (cameraProvider.focusLocked)
              Positioned(
                left: x + 40,
                top: y - 52,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'AF-L',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReticlePainterWidget extends StatefulWidget {
  final bool locked;

  const _ReticlePainterWidget({required this.locked});

  @override
  State<_ReticlePainterWidget> createState() => _ReticlePainterWidgetState();
}

class _ReticlePainterWidgetState extends State<_ReticlePainterWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      lowerBound: 1.35,
      upperBound: 1.0,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.scale(
          scale: _controller.value,
          child: SizedBox(
            width: 88,
            height: 88,
            child: CustomPaint(
              painter: _ReticlePainter(color: widget.locked
                  ? Colors.amber
                  : Colors.tealAccent),
            ),
          ),
        );
      },
    );
  }
}

class _ReticlePainter extends CustomPainter {
  final Color color;

  _ReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const inset = 14.0;
    const len = 18.0;
    final s = size.width - inset * 2;

    // Four corner brackets
    final corners = [
      [Offset(inset, inset), Offset(1, 0), Offset(0, 1)], // top-left
      [Offset(size.width - inset, inset), Offset(-1, 0), Offset(0, 1)],
      [Offset(inset, size.height - inset), Offset(1, 0), Offset(0, -1)],
      [
        Offset(size.width - inset, size.height - inset),
        Offset(-1, 0),
        Offset(0, -1)
      ],
    ];

    for (final c in corners) {
      canvas.drawLine(c[0], c[0] + c[1] * len, paint);
      canvas.drawLine(c[0], c[0] + c[2] * len, paint);
    }

    // Center dot
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      2,
      Paint()..color = color,
    );
    // Outer faint box
    canvas.drawRect(
      Rect.fromLTWH(inset, inset, s, s),
      paint..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.color != color;
}

/// Vertical exposure compensation slider shown next to the focus reticle.
class ExposureSlider extends StatelessWidget {
  final CameraProvider cameraProvider;

  const ExposureSlider({super.key, required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    final features = cameraProvider.features;
    if (!features.exposureOffset) return const SizedBox.shrink();

    final min = cameraProvider.minExposureOffset;
    final max = cameraProvider.maxExposureOffset;
    final step = cameraProvider.exposureStep > 0
        ? cameraProvider.exposureStep
        : 0.1;
    final value = cameraProvider.exposureOffset.clamp(min, max).toDouble();
    final divisions = ((max - min) / step).round().clamp(1, 200);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cameraProvider.evLabel,
            style: const TextStyle(
              color: Colors.tealAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(
            height: 160,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.tealAccent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: (v) => cameraProvider.setExposureOffsetEv(v),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => cameraProvider.resetExposureOffset(),
            child: const Icon(
              Icons.restart_alt,
              color: Colors.white54,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}
