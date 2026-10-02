import 'dart:ui';

/// Non-destructive editing parameters for a photo.
///
/// The original image file is never modified: these parameters are the sole
/// source of truth, applied as a live [ColorFilter] preview and baked into a
/// NEW exported file. See [ImageProcessor] for the full-resolution bake.
class EditParameters {
  /// Exposure bias in stops: -2.0 .. 2.0
  final double exposure;

  /// -100 .. 100
  final double brightness;
  final double contrast;
  final double highlights;
  final double shadows;
  final double saturation;
  final double temperature;
  final double tint;

  /// 0 .. 100 (unsharp mask strength)
  final double sharpness;

  /// 0 .. 100
  final double vignette;

  /// 0 .. 100
  final double grain;

  /// 90-degree rotation steps: 0..3
  final int rotateQuarterTurns;

  /// Keystone/perspective approximation, -30 .. 30
  final double keystoneX;
  final double keystoneY;

  /// Center-crop aspect ratio (width / height). Null = keep original.
  /// 1.0 = square, 4/3, 16/9, 3/2 ...
  final double? cropAspect;

  const EditParameters({
    this.exposure = 0.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.saturation = 0.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.sharpness = 0.0,
    this.vignette = 0.0,
    this.grain = 0.0,
    this.rotateQuarterTurns = 0,
    this.keystoneX = 0.0,
    this.keystoneY = 0.0,
    this.cropAspect,
  });

  static const _maxAdjust = 100.0;

  bool get isIdentity {
    return exposure == 0 &&
        brightness == 0 &&
        contrast == 0 &&
        highlights == 0 &&
        shadows == 0 &&
        saturation == 0 &&
        temperature == 0 &&
        tint == 0 &&
        sharpness == 0 &&
        vignette == 0 &&
        grain == 0 &&
        rotateQuarterTurns == 0 &&
        keystoneX == 0 &&
        keystoneY == 0 &&
        cropAspect == null;
  }

  bool get hasGeometry =>
      rotateQuarterTurns != 0 ||
      keystoneX != 0 ||
      keystoneY != 0 ||
      cropAspect != null;

  EditParameters copyWith({
    double? exposure,
    double? brightness,
    double? contrast,
    double? highlights,
    double? shadows,
    double? saturation,
    double? temperature,
    double? tint,
    double? sharpness,
    double? vignette,
    double? grain,
    int? rotateQuarterTurns,
    double? keystoneX,
    double? keystoneY,
    double? cropAspect,
    bool clearCrop = false,
  }) {
    return EditParameters(
      exposure: exposure ?? this.exposure,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      sharpness: sharpness ?? this.sharpness,
      vignette: vignette ?? this.vignette,
      grain: grain ?? this.grain,
      rotateQuarterTurns: rotateQuarterTurns ?? this.rotateQuarterTurns,
      keystoneX: keystoneX ?? this.keystoneX,
      keystoneY: keystoneY ?? this.keystoneY,
      cropAspect: clearCrop ? null : (cropAspect ?? this.cropAspect),
    );
  }

  EditParameters reset() => const EditParameters();

  /// Clamp helper for slider updates
  static double clampAdjust(double v) => v.clamp(-_maxAdjust, _maxAdjust);
  static double clampPercent(double v) => v.clamp(0, _maxAdjust);
  static double clampExposure(double v) => v.clamp(-2.0, 2.0);

  /// Composed 4x5 color matrix for the LIVE PREVIEW.
  ///
  /// Expresses exposure, brightness, contrast, saturation, temperature and
  /// tint in a single [ColorFilter.matrix]. Highlights/shadows get a close
  /// linear approximation here and are applied precisely at export time.
  List<double> previewMatrix() {
    var m = _identity();

    // Exposure: linear gain
    final gain = _pow2(exposure);
    if (gain != 1.0) {
      m = _mul(_diag(gain), m);
    }

    // Brightness: additive offset on the 0..255 scale
    if (brightness != 0) {
      m = _mul(_offset(_b(brightness) * 0.6), m);
    }

    // Contrast: rotate around mid gray
    if (contrast != 0) {
      final f = 1.0 + _b(contrast) * 0.9;
      m = _mul(_offsetWithGain(f, -f * 127.5 + 127.5 - 127.5), m);
    }

    // Highlights (negative darkens brights, approximated) and shadows
    // (positive lifts darks): linear approximations of a curve.
    if (highlights != 0) {
      m = _mul(_offset(-_b(highlights) * 0.35), m);
    }
    if (shadows != 0) {
      m = _mul(_offset(_b(shadows) * 0.35), m);
    }

    // Saturation: luminance-preserving mix
    if (saturation != 0) {
      m = _mul(_saturation(1.0 + _b(saturation)), m);
    }

    // Temperature / tint: channel offsets
    double rOff = _b(temperature) * 25;
    double bOff = -_b(temperature) * 25;
    double gOff = -_b(tint) * 22;
    rOff += _b(tint) * 8;
    bOff += _b(tint) * 8;
    if (rOff != 0 || gOff != 0 || bOff != 0) {
      m = _mul(_channelOffset(rOff, gOff, bOff), m);
    }

    return m;
  }

  double _b(double v) => v / 100.0;

  double _pow2(double x) => _exp2(x);

  static double _exp2(double x) {
    // 2^x via pow identity: exp(x * ln2)
    final ln2 = 0.6931471805599453;
    // Taylor is unnecessary: use iterative squaring for the small range
    var result = 1.0;
    var base = 2.0;
    var n = x;
    // x may be fractional: split into integer + fraction
    final i = n.truncate();
    final f = n - i;
    for (var k = 0; k < i.abs(); k++) {
      result *= base;
    }
    if (i < 0) result = 1.0 / result;
    // 2^f for f in [0,1) via exp(f*ln2) Taylor (few terms is plenty)
    if (f != 0) {
      var term = 1.0;
      var sum = 1.0;
      var powF = f * ln2;
      for (var k = 1; k <= 8; k++) {
        term *= powF / k;
        sum += term;
      }
      result *= sum;
    }
    return result;
  }

  // ---- Color matrix helpers (4x5 row-major) ----

  static List<double> _identity() => <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0,
      ];

  static List<double> _diag(double v) => <double>[
        v, 0, 0, 0, 0, //
        0, v, 0, 0, 0, //
        0, 0, v, 0, 0, //
        0, 0, 0, 1, 0,
      ];

  static List<double> _offset(double o) => <double>[
        1, 0, 0, 0, o, //
        0, 1, 0, 0, o, //
        0, 0, 1, 0, o, //
        0, 0, 0, 1, 0,
      ];

  static List<double> _offsetWithGain(double gain, double o) => <double>[
        gain, 0, 0, 0, o, //
        0, gain, 0, 0, o, //
        0, 0, gain, 0, o, //
        0, 0, 0, 1, 0,
      ];

  static List<double> _channelOffset(double r, double g, double b) =>
      <double>[
        1, 0, 0, 0, r, //
        0, 1, 0, 0, g, //
        0, 0, 1, 0, b, //
        0, 0, 0, 1, 0,
      ];

  static List<double> _saturation(double s) {
    const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
    final sr = (1 - s) * lumR, sg = (1 - s) * lumG, sb = (1 - s) * lumB;
    return <double>[
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  /// Matrix multiplication for 4x5 color matrices: a * b.
  static List<double> _mul(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        if (col == 4) {
          sum += a[row * 5 + 4];
        }
        out[row * 5 + col] = sum;
      }
    }
    return out;
  }
}

/// Undo/redo history of [EditParameters] states.
class EditHistory {
  final List<EditParameters> _undoStack = [];
  final List<EditParameters> _redoStack = [];
  EditParameters _current;

  static const _maxDepth = 50;

  EditHistory([EditParameters? initial]) : _current = initial ?? const EditParameters();

  EditParameters get current => _current;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Commit a new state. No-op if identical to the current state.
  void push(EditParameters next) {
    if (_same(next, _current)) return;
    _undoStack.add(_current);
    if (_undoStack.length > _maxDepth) _undoStack.removeAt(0);
    _redoStack.clear();
    _current = next;
  }

  EditParameters? undo() {
    if (_undoStack.isEmpty) return null;
    _redoStack.add(_current);
    _current = _undoStack.removeLast();
    return _current;
  }

  EditParameters? redo() {
    if (_redoStack.isEmpty) return null;
    _undoStack.add(_current);
    _current = _redoStack.removeLast();
    return _current;
  }

  void clear([EditParameters? initial]) {
    _undoStack.clear();
    _redoStack.clear();
    _current = initial ?? const EditParameters();
  }

  static bool _same(EditParameters a, EditParameters b) {
    return a.exposure == b.exposure &&
        a.brightness == b.brightness &&
        a.contrast == b.contrast &&
        a.highlights == b.highlights &&
        a.shadows == b.shadows &&
        a.saturation == b.saturation &&
        a.temperature == b.temperature &&
        a.tint == b.tint &&
        a.sharpness == b.sharpness &&
        a.vignette == b.vignette &&
        a.grain == b.grain &&
        a.rotateQuarterTurns == b.rotateQuarterTurns &&
        a.keystoneX == b.keystoneX &&
        a.keystoneY == b.keystoneY &&
        a.cropAspect == b.cropAspect;
  }
}
