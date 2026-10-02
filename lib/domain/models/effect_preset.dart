import 'dart:ui';

/// A real-time color effect defined as a 4x5 color matrix (20 values,
/// row-major) that can be applied with [ColorFilter.matrix].
///
/// The same presets are used for the in-camera effect selector (applied
/// non-destructively at capture time) and as "looks" in the photo editor.
class EffectPreset {
  final String name;
  final List<double> matrix;

  const EffectPreset(this.name, this.matrix);
}

abstract final class EffectPresets {
  static const normal = EffectPreset('NORMAL', <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  /// Cooled, slightly crushed blacks - cinematic teal look
  static const cinema = EffectPreset('CINEMA', <double>[
    1.06, 0, 0, 0, -0.02, //
    0, 1.0, 0, 0, 0, //
    0, 0.04, 1.02, 0, 0.01, //
    0, 0, 0, 1, 0,
  ]);

  /// Sepia-toned, lowered saturation
  static const vintage = EffectPreset('VINTAGE', <double>[
    0.9, 0.25, 0.05, 0, 0.02, //
    0.15, 0.85, 0.05, 0, 0.02, //
    0.1, 0.2, 0.7, 0, 0.02, //
    0, 0, 0, 1, 0,
  ]);

  static const bw = EffectPreset('B&W', <double>[
    0.33, 0.59, 0.11, 0, 0, //
    0.33, 0.59, 0.11, 0, 0, //
    0.33, 0.59, 0.11, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  /// Warmer white balance
  static const warm = EffectPreset('WARM', <double>[
    1.08, 0, 0, 0, 0.01, //
    0, 1.0, 0, 0, 0, //
    0, 0, 0.9, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  /// Cooler white balance
  static const cool = EffectPreset('COOL', <double>[
    0.9, 0, 0, 0, 0, //
    0, 1.0, 0, 0, 0, //
    0, 0, 1.1, 0, 0.01, //
    0, 0, 0, 1, 0,
  ]);

  static const contrast = EffectPreset('CONTRAST', <double>[
    1.25, 0, 0, 0, -0.1, //
    0, 1.25, 0, 0, -0.1, //
    0, 0, 1.25, 0, -0.1, //
    0, 0, 0, 1, 0,
  ]);

  /// Filmic S-curve approximation with a slight warm bias
  static const film = EffectPreset('FILM', <double>[
    1.1, 0.03, 0, 0, -0.04, //
    0, 1.08, 0.02, 0, -0.03, //
    0, 0, 1.05, 0, -0.02, //
    0, 0, 0, 1, 0,
  ]);

  /// Lifted blacks, lowered contrast
  static const fade = EffectPreset('FADE', <double>[
    0.9, 0, 0, 0, 0.06, //
    0, 0.9, 0, 0, 0.06, //
    0, 0, 0.9, 0, 0.06, //
    0, 0, 0, 1, 0,
  ]);

  static const List<EffectPreset> list = [
    normal,
    cinema,
    vintage,
    bw,
    warm,
    cool,
    contrast,
    film,
    fade,
  ];

  static EffectPreset at(int index) =>
      (index >= 0 && index < list.length) ? list[index] : normal;
}
