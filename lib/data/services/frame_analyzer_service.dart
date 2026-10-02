import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Luminance statistics computed from a single camera frame.
///
/// Used by the monitoring tools (histogram, zebra, highlight warning,
/// exposure meter). Computing this from a sparsely sampled subset of the
/// frame keeps the cost negligible.
class FrameStats {
  /// 32-bin luminance histogram (bin 0 = black, 31 = white)
  final List<int> histogram;

  /// Mean luminance 0..255
  final double meanLuma;

  /// Fraction of sampled pixels at or above the highlight threshold (240)
  final double highlightRatio;

  /// Fraction of sampled pixels at or below the shadow threshold (16)
  final double shadowRatio;

  /// Total pixels sampled for these stats
  final int sampledPixels;

  const FrameStats({
    required this.histogram,
    required this.meanLuma,
    required this.highlightRatio,
    required this.shadowRatio,
    required this.sampledPixels,
  });

  static const binCount = 32;
  static const highlightThreshold = 240;
  static const shadowThreshold = 16;

  /// Most common luma bin index, for a quick exposure readout
  int get peakBin {
    var best = 0;
    var bestCount = 0;
    for (var i = 0; i < histogram.length; i++) {
      if (histogram[i] > bestCount) {
        bestCount = histogram[i];
        best = i;
      }
    }
    return best;
  }

  /// Estimated scene exposure value derived from mean luma.
  /// Mid gray (128) maps to EV 0; each ~50 luma step is ~1 EV.
  double get estimatedEv => ((meanLuma - 128) / 51.0);
}

/// Raw frame description accepted by [analyzeFrameBytes] so the analysis is
/// testable without constructing plugin types.
class RawFrame {
  final Uint8List bytes;
  final int bytesPerRow;
  final int width;
  final int height;

  /// true = 1 byte/pixel luma (YUV plane 0), false = 4 bytes/pixel RGBA/BGRA
  final bool singleChannel;

  const RawFrame({
    required this.bytes,
    required this.bytesPerRow,
    required this.width,
    required this.height,
    required this.singleChannel,
  });
}

/// Compute [FrameStats] from a [CameraImage] delivered by the monitor stream.
///
/// Handles YUV420 (plane 0 holds the luma on Android) and BGRA/RGBA (iOS).
/// Rows/columns are strided so only a small fraction of the frame is read.
FrameStats analyzeFrame(CameraImage image, {int rowStride = 6, int colStride = 6}) {
  if (image.planes.isEmpty) {
    return _emptyStats();
  }
  final plane = image.planes.first;
  return analyzeFrameBytes(
    RawFrame(
      bytes: plane.bytes,
      bytesPerRow: plane.bytesPerRow,
      width: image.width,
      height: image.height,
      singleChannel:
          image.format.group == ImageFormatGroup.yuv420 ||
              plane.bytesPerRow < image.width * 4,
    ),
    rowStride: rowStride,
    colStride: colStride,
  );
}

/// Pure frame statistics over raw bytes. Safe to call in tests.
FrameStats analyzeFrameBytes(
  RawFrame frame, {
  int rowStride = 6,
  int colStride = 6,
}) {
  final bins = List<int>.filled(FrameStats.binCount, 0);
  var count = 0;
  var sum = 0;
  var highlights = 0;
  var shadows = 0;

  final bytes = frame.bytes;
  final bytesPerPixel = frame.singleChannel ? 1 : 4;

  if (frame.width > 0 && frame.height > 0 && bytes.isNotEmpty) {
    var row = 0;
    while (row < frame.height) {
      final rowBase = row * frame.bytesPerRow;
      var col = 0;
      while (col < frame.width) {
        final idx = rowBase + col * bytesPerPixel;
        if (idx + bytesPerPixel > bytes.length) break;

        var luma = 0;
        if (frame.singleChannel) {
          luma = bytes[idx];
        } else {
          final r = bytes[idx] / 255.0;
          final g = bytes[idx + 1] / 255.0;
          final b = bytes[idx + 2] / 255.0;
          luma = ((0.2126 * r + 0.7152 * g + 0.0722 * b) * 255).round();
        }

        final bin =
            (luma * FrameStats.binCount ~/ 256).clamp(0, FrameStats.binCount - 1);
        bins[bin]++;
        sum += luma;
        count++;
        if (luma >= FrameStats.highlightThreshold) highlights++;
        if (luma <= FrameStats.shadowThreshold) shadows++;

        col += colStride;
      }
      row += rowStride;
    }
  }

  if (count == 0) return _emptyStats();

  return FrameStats(
    histogram: bins,
    meanLuma: sum / count,
    highlightRatio: highlights / count,
    shadowRatio: shadows / count,
    sampledPixels: count,
  );
}

FrameStats _emptyStats() => FrameStats(
      histogram: List<int>.filled(FrameStats.binCount, 0),
      meanLuma: 0,
      highlightRatio: 0,
      shadowRatio: 0,
      sampledPixels: 0,
    );
