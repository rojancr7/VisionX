import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models/media_item.dart';
import '../providers/camera_provider.dart';
import '../widgets/camera_preview_widget.dart';
import '../widgets/camera_controls_widget.dart';
import '../widgets/camera_header_widget.dart';
import '../widgets/camera_hud_widget.dart';
import '../widgets/effects_panel.dart';
import '../widgets/monitoring_widgets.dart';
import 'gallery_screen.dart';
import 'photo_preview_screen.dart';

/// Main camera screen - professional viewfinder layout:
///
///   [ header: flash/HDR/timer | grid/level/monitor/manual/effects ]
///   [ HUD (top right) + histogram/meter (top left)               ]
///   [ preview with tap-to-focus, pinch-zoom, grid, level, zebra   ]
///   [ effects panel (when open)                                   ]
///   [ lens chips / zoom wheel / mode / shutter row                ]
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CameraProvider>();
      provider.onPhotoCaptured = _onPhotoCaptured;
      provider.initializeCamera();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final provider = context.read<CameraProvider>();

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        provider.pauseCamera();
        break;
      case AppLifecycleState.resumed:
        provider.resumeCamera();
        break;
    }
  }

  /// Push the capture preview (EDIT / SAVE / SHARE / DELETE / RETAKE)
  void _onPhotoCaptured(MediaItem item) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PhotoPreviewScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<CameraProvider>(
        builder: (context, provider, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview + gestures + overlays
              CameraPreviewWidget(cameraProvider: provider),

              // Header controls
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: CameraHeaderWidget(cameraProvider: provider),
              ),

              // Professional HUD (top right, under header)
              Positioned(
                top: 96,
                right: 0,
                child: CameraHudWidget(cameraProvider: provider),
              ),

              // Histogram + exposure meter (top left)
              Positioned(
                top: 96,
                left: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (provider.settings.histogramEnabled)
                      HistogramWidget(stats: provider.frameStats),
                    if (provider.settings.exposureMeterEnabled) ...[
                      const SizedBox(height: 8),
                      ExposureMeterWidget(stats: provider.frameStats),
                    ],
                  ],
                ),
              ),

              // Recording indicator
              if (provider.isRecording)
                Positioned(
                  top: 110,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _RecordingIndicator(
                      formattedDuration: provider.formattedDuration,
                    ),
                  ),
                ),

              // Countdown display
              if (provider.isCountingDown)
                Center(
                  child: _CountdownDisplay(value: provider.countdownValue),
                ),

              // Error banner
              if (provider.errorMessage != null &&
                  provider.state != CameraState.error)
                Positioned(
                  bottom: 300,
                  left: 24,
                  right: 24,
                  child: _ErrorBanner(
                    message: provider.errorMessage!,
                    onDismiss: () => provider.clearError(),
                  ),
                ),

              // Controls deck
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: CameraControlsWidget(
                  cameraProvider: provider,
                  onGalleryTap: _openGallery,
                ),
              ),

              // Effects panel (slides over the controls)
              if (provider.effectsPanelOpen)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: EffectsPanel(cameraProvider: provider),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openGallery() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GalleryScreen()),
    );
    if (!mounted) return;
    context.read<CameraProvider>().clearError();
  }
}

class _RecordingIndicator extends StatelessWidget {
  final String formattedDuration;

  const _RecordingIndicator({required this.formattedDuration});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BlinkingDot(),
          const SizedBox(width: 8),
          Text(
            formattedDuration,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
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
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _controller.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class _CountdownDisplay extends StatelessWidget {
  final int value;

  const _CountdownDisplay({required this.value});

  @override
  Widget build(BuildContext context) {
    if (value <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Text(
        value.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 64,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
