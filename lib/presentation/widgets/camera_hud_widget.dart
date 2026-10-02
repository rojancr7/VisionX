import 'package:flutter/material.dart';
import '../providers/camera_provider.dart';

/// Clean professional HUD showing live camera settings that the plugin
/// actually reports: resolution, zoom, exposure compensation, flash state
/// and the selected effect. Values that the camera API does not expose
/// (ISO, shutter, WB) are never faked.
class CameraHudWidget extends StatelessWidget {
  final CameraProvider cameraProvider;

  const CameraHudWidget({super.key, required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    if (!cameraProvider.settings.hudEnabled) return const SizedBox.shrink();

    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(top: 4, right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _badge(cameraProvider.resolutionLabel),
            const SizedBox(height: 4),
            _badge(cameraProvider.zoomLabel),
            if (cameraProvider.exposureOffset != 0) ...[
              const SizedBox(height: 4),
              _badge(cameraProvider.evLabel),
            ],
            if (cameraProvider.settings.flashMode.name != 'off' &&
                !cameraProvider.isFrontCamera) ...[
              const SizedBox(height: 4),
              _badge('FLASH ${cameraProvider.settings.flashMode.name.toUpperCase()}'),
            ],
            if (cameraProvider.settings.effectIndex != 0) ...[
              const SizedBox(height: 4),
              _badge(
                cameraProvider.effectName,
                highlight: true,
              ),
            ],
            if (cameraProvider.focusLocked) ...[
              const SizedBox(height: 4),
              _badge('AF-L', highlight: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: highlight ? Colors.tealAccent : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
