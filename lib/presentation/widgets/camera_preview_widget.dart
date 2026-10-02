import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../providers/camera_provider.dart';
import 'exposure_control.dart';
import 'monitoring_widgets.dart';

/// Camera preview with professional gestures:
/// - Tap to focus + meter (shows reticle + EV slider)
/// - Hold to lock focus/exposure
/// - Pinch to zoom
/// Plus static overlays: grid, level, zebra.
class CameraPreviewWidget extends StatefulWidget {
  final CameraProvider cameraProvider;

  const CameraPreviewWidget({super.key, required this.cameraProvider});

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  double? _pinchStartFactor;

  @override
  Widget build(BuildContext context) {
    final provider = widget.cameraProvider;
    final controller = provider.controller;
    final state = provider.state;

    if (state == CameraState.initializing || controller == null) {
      return _buildInitializing();
    }

    if (state == CameraState.error) {
      return _buildError(provider);
    }

    if (!controller.value.isInitialized) {
      return _buildInitializing();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(details.globalPosition);
        provider.tapToFocus(Offset(
          local.dx / box.size.width,
          local.dy / box.size.height,
        ));
      },
      onLongPressStart: (_) => provider.toggleFocusLock(),
      onScaleStart: (details) {
        _pinchStartFactor = provider.zoomFactor;
      },
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) return;
        final start = _pinchStartFactor;
        if (start == null) return;
        provider.setZoomFactor(start * details.scale);
      },
      onScaleEnd: (_) => _pinchStartFactor = null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live preview
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1,
                height: controller.value.previewSize?.width ?? 1,
                child: CameraPreview(controller),
              ),
            ),
          ),

          // Rule-of-thirds grid
          if (provider.settings.gridEnabled) const GridOverlay(),

          // Horizon level
          if (provider.settings.levelEnabled)
            Center(child: LevelIndicator(rollDegrees: provider.rollDegrees)),

          // Zebra clipping warning
          if (provider.settings.zebraEnabled && provider.frameStats != null)
            ZebraOverlay(highlightRatio: provider.frameStats!.highlightRatio),

          // Focus reticle + EV slider
          FocusReticle(cameraProvider: provider),
          if (provider.focusPoint != null)
            Positioned(
              right: 16,
              top: 140,
              child: ExposureSlider(cameraProvider: provider),
            ),
        ],
      ),
    );
  }

  Widget _buildInitializing() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Initializing camera...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(CameraProvider provider) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              provider.errorMessage ?? 'Camera error',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.initializeCamera(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
