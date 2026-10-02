import 'dart:math' as math;
import 'dart:ui' show ColorFilter;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/models/edit_parameters.dart';
import '../../domain/models/effect_preset.dart';

/// Non-destructive image processing.
///
/// All heavy functions run inside an isolate (call via [compute]) and always
/// produce a NEW file - the original photo bytes are never modified.
abstract final class ImageProcessor {
  static const exportJpegQuality = 95;

  /// Maximum exported dimension (longest side). Keeps memory and processing
  /// time bounded on high-megapixel sensors.
  static const maxExportDimension = 4096;

  /// Apply an [EffectPreset] color matrix to JPEG bytes. Runs in an isolate.
  static Future<Uint8List> applyEffect(
    Uint8List jpegBytes,
    EffectPreset preset,
  ) {
    return compute(_applyEffectIsolate, (jpegBytes, preset.matrix));
  }

  /// Bake [EditParameters] into JPEG bytes at full resolution.
  /// Runs in an isolate.
  static Future<Uint8List> exportEdited(
    Uint8List jpegBytes,
    EditParameters params,
  ) {
    return compute(_exportIsolate, (jpegBytes, params));
  }

  static Uint8List _applyEffectIsolate((Uint8List, List<double>) input) {
    final (bytes, matrix) = input;
    final image = img.decodeJpg(bytes);
    if (image == null) return bytes;
    _applyColorMatrix(image, matrix);
    return Uint8List.fromList(img.encodeJpg(image, quality: exportJpegQuality));
  }

  static Uint8List _exportIsolate((Uint8List, EditParameters) input) {
    final (bytes, params) = input;
    var image = img.decodeJpg(bytes);
    if (image == null) return bytes;

    image = _applyGeometry(image, params);
    _applyAdjustments(image, params);
    if (params.sharpness > 0) _applySharpness(image, params.sharpness);

    return Uint8List.fromList(img.encodeJpg(image, quality: exportJpegQuality));
  }

  // ---- Geometry ----

  static img.Image _applyGeometry(img.Image image, EditParameters params) {
    // Downscale first when the sensor produced something huge
    if (image.width > maxExportDimension || image.height > maxExportDimension) {
      final scale =
          maxExportDimension / math.max(image.width, image.height).toDouble();
      image = img.copyResize(
        image,
        width: (image.width * scale).round(),
        height: (image.height * scale).round(),
      );
    }

    // Center crop to the selected aspect ratio
    final aspect = params.cropAspect;
    if (aspect != null && aspect > 0) {
      final w = image.width;
      final h = image.height;
      final current = w / h;
      int cropW;
      int cropH;
      if (current > aspect) {
        cropH = h;
        cropW = (h * aspect).round();
      } else {
        cropW = w;
        cropH = (w / aspect).round();
      }
      image = img.copyCrop(
        image,
        x: (w - cropW) ~/ 2,
        y: (h - cropH) ~/ 2,
        width: cropW,
        height: cropH,
      );
    }

    if (params.rotateQuarterTurns != 0) {
      image = img.copyRotate(image, angle: (params.rotateQuarterTurns % 4) * 90);
    }

    if (params.keystoneX != 0 || params.keystoneY != 0) {
      image = _keystone(image, params.keystoneX / 100.0, params.keystoneY / 100.0);
    }

    return image;
  }

  /// Simple trapezoid keystone with bilinear sampling (perspective
  /// approximation for architectural shots).
  static img.Image _keystone(img.Image src, double kx, double ky) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);
    final cx = w / 2.0;
    final cy = h / 2.0;
    const maxScale = 0.25;

    for (var y = 0; y < h; y++) {
      final v = (y - cy) / cy; // -1 top .. 1 bottom
      for (var x = 0; x < w; x++) {
        final u = (x - cx) / cx;
        var sx = x.toDouble();
        var sy = y.toDouble();

        if (ky != 0) {
          final scale = 1.0 - ky * maxScale * v;
          if (scale.abs() > 0.01) sx = cx + (x - cx) / scale;
        }
        if (kx != 0) {
          final scale = 1.0 - kx * maxScale * u;
          if (scale.abs() > 0.01) sy = cy + (y - cy) / scale;
        }

        final c = _sampleBilinear(src, sx, sy);
        out.setPixelRgb(x, y, c.$1, c.$2, c.$3);
      }
    }
    return out;
  }

  static (double, double, double) _sampleBilinear(
    img.Image src,
    double x,
    double y,
  ) {
    final fx = x.clamp(0.0, src.width - 1.0);
    final fy = y.clamp(0.0, src.height - 1.0);
    final x0 = fx.floor();
    final y0 = fy.floor();
    final x1 = math.min(x0 + 1, src.width - 1);
    final y1 = math.min(y0 + 1, src.height - 1);
    final dx = fx - x0;
    final dy = fy - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    double ch(num a, num b, num c, num d) =>
        (a * (1 - dx) + b * dx) * (1 - dy) + (c * (1 - dx) + d * dx) * dy;

    return (
      ch(p00.r, p10.r, p01.r, p11.r).toDouble(),
      ch(p00.g, p10.g, p01.g, p11.g).toDouble(),
      ch(p00.b, p10.b, p01.b, p11.b).toDouble(),
    );
  }

  // ---- Color ----

  /// Apply a 4x5 color matrix (0..255 scale, like ColorFilter.matrix).
  static void _applyColorMatrix(img.Image image, List<double> m) {
    final w = image.width;
    final h = image.height;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        p.r = _clamp8(m[0] * r + m[1] * g + m[2] * b + m[4]).round();
        p.g = _clamp8(m[5] * r + m[6] * g + m[7] * b + m[9]).round();
        p.b = _clamp8(m[10] * r + m[11] * g + m[12] * b + m[14]).round();
      }
    }
  }

  static void _applyAdjustments(img.Image image, EditParameters params) {
    if (params.isIdentity) return;

    final evGain = math.pow(2.0, params.exposure).toDouble();
    final bright = params.brightness / 100.0 * 0.6;
    final contrast = 1.0 + params.contrast / 100.0 * 0.9;
    final highlights = params.highlights / 100.0;
    final shadows = params.shadows / 100.0;
    final sat = 1.0 + params.saturation / 100.0;
    final temp = params.temperature / 100.0 * 0.1;
    final tint = params.tint / 100.0;
    final vignette = params.vignette / 100.0;
    final grain = params.grain / 100.0;

    final w = image.width;
    final h = image.height;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        var r = p.r / 255.0;
        var g = p.g / 255.0;
        var b = p.b / 255.0;

        // Exposure gain + brightness
        r = r * evGain + bright;
        g = g * evGain + bright;
        b = b * evGain + bright;

        // Contrast around mid gray
        r = (r - 0.5) * contrast + 0.5;
        g = (g - 0.5) * contrast + 0.5;
        b = (b - 0.5) * contrast + 0.5;

        // Highlights: push the bright half toward black (or white)
        if (highlights != 0) {
          r = _applyHighlights(r, highlights);
          g = _applyHighlights(g, highlights);
          b = _applyHighlights(b, highlights);
        }

        // Shadows: lift (or deepen) the dark half
        if (shadows != 0) {
          r = _applyShadows(r, shadows);
          g = _applyShadows(g, shadows);
          b = _applyShadows(b, shadows);
        }

        // Saturation around luma
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        r = luma + (r - luma) * sat;
        g = luma + (g - luma) * sat;
        b = luma + (b - luma) * sat;

        // Temperature / tint
        r += temp + tint * 0.03;
        g -= tint * 0.09;
        b += -temp + tint * 0.03;

        // Vignette
        if (vignette > 0) {
          final dx = (x / w - 0.5) * 2;
          final dy = (y / h - 0.5) * 2;
          final dist = math.sqrt(dx * dx + dy * dy) / math.sqrt2;
          final t = ((dist - 0.45) / 0.55).clamp(0.0, 1.0);
          final falloff = 1.0 - t * t * (3 - 2 * t) * vignette * 0.85;
          r *= falloff;
          g *= falloff;
          b *= falloff;
        }

        // Grain
        if (grain > 0) {
          final n = (_hash(x, y) / 2147483647.0 - 0.5) * grain * 0.25;
          r += n;
          g += n;
          b += n;
        }

        p.r = (r.clamp(0.0, 1.0) * 255).round();
        p.g = (g.clamp(0.0, 1.0) * 255).round();
        p.b = (b.clamp(0.0, 1.0) * 255).round();
      }
    }
  }

  /// h > 0 recovers (darkens) the bright half, h < 0 brightens it.
  static double _applyHighlights(double v, double h) {
    if (v <= 0.5) return v;
    return v - (v - 0.5) * h * 0.8;
  }

  /// s > 0 lifts the dark half, s < 0 deepens it.
  static double _applyShadows(double v, double s) {
    if (v >= 0.5) return v;
    return v + (0.5 - v) * s * 0.8;
  }

  static int _hash(int x, int y) {
    var h = x * 374761393 + y * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return h & 0x7FFFFFFF;
  }

  /// Unsharp mask via separable 3x3 box blur on the luma plane.
  static void _applySharpness(img.Image image, double strength) {
    final w = image.width;
    final h = image.height;
    final amount = strength / 100.0 * 1.2;

    final luma = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        luma[y * w + x] = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      }
    }

    final blurred = Float32List(w * h);
    // Horizontal pass
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - 1);
        final x1 = math.min(w - 1, x + 1);
        blurred[y * w + x] =
            (luma[y * w + x0] + luma[y * w + x] + luma[y * w + x1]) / 3.0;
      }
    }
    // Vertical pass back into `luma`
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - 1);
      final y1 = math.min(h - 1, y + 1);
      for (var x = 0; x < w; x++) {
        luma[y * w + x] =
            (blurred[y0 * w + x] + blurred[y * w + x] + blurred[y1 * w + x]) /
                3.0;
      }
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final detail = luma[y * w + x] - blurred[y * w + x];
        if (detail == 0) continue;
        final p = image.getPixel(x, y);
        p.r = (p.r + detail * amount).round().clamp(0, 255);
        p.g = (p.g + detail * amount).round().clamp(0, 255);
        p.b = (p.b + detail * amount).round().clamp(0, 255);
      }
    }
  }

  static double _clamp8(double v) => v.clamp(0.0, 255.0);
}

/// Convenience for building a preview [ColorFilter] from edit parameters.
ColorFilter editPreviewFilter(EditParameters params) {
  return ColorFilter.matrix(params.previewMatrix());
}
