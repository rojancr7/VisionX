import 'dart:ui';
import 'package:camera/camera.dart';

/// Camera settings model.
///
/// Holds both capture settings and the on/off state of the professional
/// UI overlays (grid, level, HUD, monitoring tools, effects).
class CameraSettings {
  final FlashMode flashMode;
  final CameraLensDirection lensDirection;
  final double zoomLevel;
  final AspectRatioType aspectRatio;
  final int? timerSeconds;

  /// Exposure compensation in EV steps (e.g. -2.0 .. 2.0)
  final double exposureOffset;

  /// UI overlays
  final bool gridEnabled;
  final bool levelEnabled;
  final bool hudEnabled;

  /// Monitoring tools
  final bool histogramEnabled;
  final bool zebraEnabled;
  final bool highlightWarningEnabled;
  final bool exposureMeterEnabled;

  /// Index into [EffectPresets.list] (0 = normal)
  final int effectIndex;

  const CameraSettings({
    this.flashMode = FlashMode.auto,
    this.lensDirection = CameraLensDirection.back,
    this.zoomLevel = 1.0,
    this.aspectRatio = AspectRatioType.ratio4_3,
    this.timerSeconds,
    this.exposureOffset = 0.0,
    this.gridEnabled = false,
    this.levelEnabled = false,
    this.hudEnabled = true,
    this.histogramEnabled = false,
    this.zebraEnabled = false,
    this.highlightWarningEnabled = false,
    this.exposureMeterEnabled = false,
    this.effectIndex = 0,
  });

  CameraSettings copyWith({
    FlashMode? flashMode,
    CameraLensDirection? lensDirection,
    double? zoomLevel,
    AspectRatioType? aspectRatio,
    int? timerSeconds,
    double? exposureOffset,
    bool? gridEnabled,
    bool? levelEnabled,
    bool? hudEnabled,
    bool? histogramEnabled,
    bool? zebraEnabled,
    bool? highlightWarningEnabled,
    bool? exposureMeterEnabled,
    int? effectIndex,
  }) {
    return CameraSettings(
      flashMode: flashMode ?? this.flashMode,
      lensDirection: lensDirection ?? this.lensDirection,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      exposureOffset: exposureOffset ?? this.exposureOffset,
      gridEnabled: gridEnabled ?? this.gridEnabled,
      levelEnabled: levelEnabled ?? this.levelEnabled,
      hudEnabled: hudEnabled ?? this.hudEnabled,
      histogramEnabled: histogramEnabled ?? this.histogramEnabled,
      zebraEnabled: zebraEnabled ?? this.zebraEnabled,
      highlightWarningEnabled:
          highlightWarningEnabled ?? this.highlightWarningEnabled,
      exposureMeterEnabled: exposureMeterEnabled ?? this.exposureMeterEnabled,
      effectIndex: effectIndex ?? this.effectIndex,
    );
  }
}

enum AspectRatioType {
  ratio4_3,
  ratio16_9,
  ratio1_1,
}

extension AspectRatioExtension on AspectRatioType {
  double get ratio {
    switch (this) {
      case AspectRatioType.ratio4_3:
        return 4 / 3;
      case AspectRatioType.ratio16_9:
        return 16 / 9;
      case AspectRatioType.ratio1_1:
        return 1 / 1;
    }
  }

  Size get size {
    switch (this) {
      case AspectRatioType.ratio4_3:
        return const Size(1920, 1440);
      case AspectRatioType.ratio16_9:
        return const Size(1920, 1080);
      case AspectRatioType.ratio1_1:
        return const Size(1080, 1080);
    }
  }
}
