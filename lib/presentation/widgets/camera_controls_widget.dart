import 'dart:io';

import 'package:flutter/material.dart';
import '../../domain/models/media_item.dart';
import '../providers/camera_provider.dart';
import 'lens_selector.dart';
import 'zoom_wheel.dart';

/// Bottom control deck: mode selector, lens chips, zoom wheel and the
/// shutter row (thumbnail / shutter / camera switch).
class CameraControlsWidget extends StatelessWidget {
  final CameraProvider cameraProvider;
  final VoidCallback? onGalleryTap;

  const CameraControlsWidget({
    super.key,
    required this.cameraProvider,
    this.onGalleryTap,
  });

  @override
  Widget build(BuildContext context) {
    final locked =
        cameraProvider.isRecording || cameraProvider.isCountingDown;
    final zoomSupported =
        cameraProvider.maxZoomFactor > cameraProvider.minZoomFactor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.75),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lens chips (only with multiple real back lenses)
            if (!locked) LensSelector(cameraProvider: cameraProvider),
            if (!locked) const SizedBox(height: 8),

            // Zoom wheel
            if (!locked && zoomSupported)
              ZoomWheel(cameraProvider: cameraProvider),
            if (!locked && zoomSupported) const SizedBox(height: 10),

            // Mode selector
            _ModeSelector(cameraProvider: cameraProvider),
            const SizedBox(height: 16),

            // Shutter row
            _ShutterRow(
              cameraProvider: cameraProvider,
              locked: locked,
              onGalleryTap: onGalleryTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final CameraProvider cameraProvider;

  const _ModeSelector({required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    final locked =
        cameraProvider.isRecording || cameraProvider.isCountingDown;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ModeButton(
          label: 'PHOTO',
          selected: cameraProvider.captureMode == CaptureMode.photo,
          enabled: !locked,
          onTap: () => cameraProvider.setCaptureMode(CaptureMode.photo),
        ),
        const SizedBox(width: 28),
        _ModeButton(
          label: 'VIDEO',
          selected: cameraProvider.captureMode == CaptureMode.video,
          enabled: !locked,
          onTap: () => cameraProvider.setCaptureMode(CaptureMode.video),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? Colors.tealAccent
              : (enabled ? Colors.white70 : Colors.white24),
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _ShutterRow extends StatelessWidget {
  final CameraProvider cameraProvider;
  final bool locked;
  final VoidCallback? onGalleryTap;

  const _ShutterRow({
    required this.cameraProvider,
    required this.locked,
    this.onGalleryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Last captured thumbnail / gallery
        _ThumbnailButton(
          cameraProvider: cameraProvider,
          onTap: onGalleryTap,
        ),

        // Shutter
        _CaptureButton(
          cameraProvider: cameraProvider,
        ),

        // Camera switch
        Opacity(
          opacity: locked ? 0.35 : 1.0,
          child: IconButton(
            onPressed: locked ? null : () => cameraProvider.switchCamera(),
            icon: const Icon(
              Icons.flip_camera_ios_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThumbnailButton extends StatelessWidget {
  final CameraProvider cameraProvider;
  final VoidCallback? onTap;

  const _ThumbnailButton({required this.cameraProvider, this.onTap});

  @override
  Widget build(BuildContext context) {
    final path = cameraProvider.lastCapturedPath;
    final type = cameraProvider.lastCapturedType;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white54, width: 1.5),
          color: Colors.black45,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.5),
          child: path != null && type == MediaType.photo
              ? Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.photo_library_outlined,
                    color: Colors.white70,
                    size: 22,
                  ),
                )
              : const Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white70,
                  size: 22,
                ),
        ),
      ),
    );
  }
}

class _CaptureButton extends StatefulWidget {
  final CameraProvider cameraProvider;

  const _CaptureButton({required this.cameraProvider});

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.cameraProvider;
    // Only block while an operation is in flight - the button must stay
    // tappable to stop an active recording.
    final isCapturing = provider.state == CameraState.capturing;
    final isVideoMode = provider.captureMode == CaptureMode.video;

    return GestureDetector(
      onTapDown: (_) {
        if (!isCapturing) _controller.forward();
      },
      onTapUp: (_) {
        _controller.reverse();
        if (!isCapturing) provider.capture();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Opacity(
          opacity: isCapturing ? 0.5 : 1.0,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: provider.isRecording
                    ? Colors.red
                    : Colors.white.withValues(alpha: 0.9),
                width: 4,
              ),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: isVideoMode && provider.isRecording
                    ? _stopSquare()
                    : _shutterCircle(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shutterCircle() {
    return Container(
      key: const ValueKey('shutter'),
      width: 58,
      height: 58,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _stopSquare() {
    return Container(
      key: const ValueKey('stop'),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}
