import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vision_x/data/services/frame_analyzer_service.dart';
import 'package:vision_x/data/services/media_service.dart';
import 'package:vision_x/domain/models/camera_settings.dart';
import 'package:vision_x/domain/models/effect_preset.dart';
import 'package:vision_x/domain/models/edit_parameters.dart';
import 'package:vision_x/main.dart';
import 'package:vision_x/presentation/providers/camera_provider.dart';

void main() {
  group('VisionXApp', () {
    testWidgets('builds and shows the camera initializing screen',
        (tester) async {
      await tester.pumpWidget(const VisionXApp());

      // The first frame always shows the initializing state; camera
      // initialization starts after this frame and needs platform plugins
      // (unavailable in tests).
      expect(find.text('Initializing camera...'), findsOneWidget);
    });
  });

  group('CameraSettings', () {
    test('copyWith replaces only the provided fields', () {
      const settings = CameraSettings();

      final updated = settings.copyWith(
        flashMode: FlashMode.torch,
        zoomLevel: 2.5,
        timerSeconds: 10,
        gridEnabled: true,
        effectIndex: 2,
      );

      expect(updated.flashMode, FlashMode.torch);
      expect(updated.zoomLevel, 2.5);
      expect(updated.timerSeconds, 10);
      expect(updated.gridEnabled, isTrue);
      expect(updated.effectIndex, 2);
      // Unspecified fields keep their values
      expect(updated.lensDirection, settings.lensDirection);
      expect(updated.aspectRatio, settings.aspectRatio);
      expect(updated.hudEnabled, isTrue);
      // Original is unchanged
      expect(settings.flashMode, FlashMode.auto);
      expect(settings.timerSeconds, isNull);
      expect(settings.gridEnabled, isFalse);
    });

    test('aspect ratio values are correct', () {
      expect(AspectRatioType.ratio4_3.ratio, closeTo(4 / 3, 0.0001));
      expect(AspectRatioType.ratio16_9.ratio, closeTo(16 / 9, 0.0001));
      expect(AspectRatioType.ratio1_1.ratio, 1.0);
    });
  });

  group('EffectPresets', () {
    test('exposes the full professional preset list', () {
      expect(EffectPresets.list.length, 9);
      expect(EffectPresets.list.first.name, 'NORMAL');
    });

    test('every preset matrix is a valid 4x5 color matrix', () {
      for (final preset in EffectPresets.list) {
        expect(preset.matrix.length, 20, reason: preset.name);
        // Alpha row must keep alpha untouched
        expect(preset.matrix[15], 0, reason: preset.name);
        expect(preset.matrix[16], 0, reason: preset.name);
        expect(preset.matrix[17], 0, reason: preset.name);
        expect(preset.matrix[18], 1, reason: preset.name);
        expect(preset.matrix[19], 0, reason: preset.name);
      }
    });

    test('at() clamps out-of-range indices to normal', () {
      expect(EffectPresets.at(0), same(EffectPresets.normal));
      expect(EffectPresets.at(8), same(EffectPresets.fade));
      expect(EffectPresets.at(-1), same(EffectPresets.normal));
      expect(EffectPresets.at(99), same(EffectPresets.normal));
    });
  });

  group('EditParameters', () {
    test('defaults are identity', () {
      const params = EditParameters();
      expect(params.isIdentity, isTrue);
      expect(params.hasGeometry, isFalse);
    });

    test('clamps helper values', () {
      expect(EditParameters.clampAdjust(150), 100);
      expect(EditParameters.clampAdjust(-150), -100);
      expect(EditParameters.clampPercent(-5), 0);
      expect(EditParameters.clampExposure(5), 2.0);
      expect(EditParameters.clampExposure(-5), -2.0);
    });

    test('previewMatrix is always a 20-entry color matrix', () {
      const params = EditParameters(
        exposure: 0.5,
        contrast: 30,
        saturation: -50,
        temperature: 20,
      );
      final matrix = params.previewMatrix();
      expect(matrix.length, 20);
      // Alpha row unchanged
      expect(matrix[15], 0);
      expect(matrix[18], 1);
      // Identity parameters produce the identity matrix
      const identity = EditParameters();
      expect(identity.previewMatrix()[0], 1);
      expect(identity.previewMatrix()[6], 1);
    });

    test('reset returns a fresh identity', () {
      final params = const EditParameters(contrast: 50).reset();
      expect(params.isIdentity, isTrue);
    });

    test('clearCrop removes the crop aspect', () {
      final withCrop = const EditParameters().copyWith(cropAspect: 1.0);
      expect(withCrop.cropAspect, 1.0);
      expect(withCrop.hasGeometry, isTrue);

      final cleared = withCrop.copyWith(clearCrop: true);
      expect(cleared.cropAspect, isNull);
    });
  });

  group('EditHistory', () {
    test('push, undo and redo', () {
      final history = EditHistory();
      expect(history.canUndo, isFalse);

      history.push(const EditParameters(contrast: 10));
      history.push(const EditParameters(contrast: 20));
      expect(history.current.contrast, 20);
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);

      history.undo();
      expect(history.current.contrast, 10);
      expect(history.canRedo, isTrue);

      history.redo();
      expect(history.current.contrast, 20);

      history.undo();
      history.undo();
      expect(history.current.isIdentity, isTrue);
    });

    test('pushing an identical state is a no-op', () {
      final history = EditHistory();
      history.push(const EditParameters(contrast: 10));
      history.push(const EditParameters(contrast: 10));
      expect(history.canUndo, isTrue);
      // Only one real transition happened
      history.undo();
      expect(history.canUndo, isFalse);
    });

    test('a new push clears the redo stack and replaces the state', () {
      final history = EditHistory();
      history.push(const EditParameters(contrast: 10));
      history.push(const EditParameters(contrast: 20));
      history.undo();
      expect(history.canRedo, isTrue);
      history.push(const EditParameters(brightness: 5));
      expect(history.canRedo, isFalse);
      // push replaces the full state - the editor always passes a merged
      // copyWith() result, so no fields are lost in practice
      expect(history.current.brightness, 5);
      expect(history.current.contrast, 0);
    });

    test('clear resets everything', () {
      final history = EditHistory();
      history.push(const EditParameters(contrast: 10));
      history.undo();
      history.clear();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(history.current.isIdentity, isTrue);
    });
  });

  group('FrameStats / analyzeFrameBytes', () {
    test('pure luma frame produces a correct histogram', () {
      // 12x12 frame, stride 6: sampled rows 0,6 and cols 0,6 => 4 px
      final bytes = Uint8List(12 * 12);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = 128; // mid gray
      }
      final stats = analyzeFrameBytes(RawFrame(
        bytes: bytes,
        bytesPerRow: 12,
        width: 12,
        height: 12,
        singleChannel: true,
      ));

      expect(stats.sampledPixels, 4);
      expect(stats.meanLuma, 128);
      expect(stats.highlightRatio, 0);
      expect(stats.shadowRatio, 0);
      // Mid gray lands in bin 16 (128 * 32 / 256)
      expect(stats.histogram[16], 4);
      expect(stats.estimatedEv, closeTo(0, 0.01));
    });

    test('detects highlights and shadows', () {
      final bytes = Uint8List(12 * 12);
      for (var i = 0; i < bytes.length; i++) {
        // Left half white, right half black; sampled cols 0 and 6 hit both
        bytes[i] = (i % 12) < 6 ? 250 : 5;
      }
      final stats = analyzeFrameBytes(RawFrame(
        bytes: bytes,
        bytesPerRow: 12,
        width: 12,
        height: 12,
        singleChannel: true,
      ));

      expect(stats.highlightRatio, greaterThan(0));
      expect(stats.shadowRatio, greaterThan(0));
    });

    test('RGBA frames use weighted luma', () {
      // 2x2 BGRA frame: all pixels pure green (0,255,0)
      final bytes = Uint8List(2 * 2 * 4);
      for (var i = 0; i < 4; i++) {
        bytes[i * 4] = 0;
        bytes[i * 4 + 1] = 255;
        bytes[i * 4 + 2] = 0;
        bytes[i * 4 + 3] = 255;
      }
      final stats = analyzeFrameBytes(RawFrame(
        bytes: bytes,
        bytesPerRow: 8,
        width: 2,
        height: 2,
        singleChannel: false,
      ));

      expect(stats.sampledPixels, greaterThanOrEqualTo(1));
      // Green-dominant luma ~0.7152 * 255 ~ 182
      expect(stats.meanLuma, closeTo(182, 2));
    });

    test('empty input yields empty stats without crashing', () {
      final stats = analyzeFrameBytes(RawFrame(
        bytes: Uint8List(0),
        bytesPerRow: 0,
        width: 0,
        height: 0,
        singleChannel: true,
      ));
      expect(stats.sampledPixels, 0);
      expect(stats.histogram.length, FrameStats.binCount);
    });
  });

  group('MediaService', () {
    final service = MediaService();

    test('generates photo filenames with jpg extension', () {
      final name = service.generatePhotoFilename();
      expect(name.startsWith('IMG_'), isTrue);
      expect(name.endsWith('.jpg'), isTrue);
    });

    test('generates video filenames with mp4 extension', () {
      final name = service.generateVideoFilename();
      expect(name.startsWith('VID_'), isTrue);
      expect(name.endsWith('.mp4'), isTrue);
    });

    test('generated filenames are unique', () {
      final names = List.generate(50, (_) => service.generatePhotoFilename());
      expect(names.toSet().length, 50);
    });
  });

  group('CameraProvider', () {
    test('formats recording duration as MM:SS', () {
      final provider = CameraProvider();
      addTearDown(provider.dispose);

      expect(provider.formattedDuration, '00:00');
    });

    test('starts in initializing state with no capture yet', () {
      final provider = CameraProvider();
      addTearDown(provider.dispose);

      expect(provider.state, CameraState.initializing);
      expect(provider.isRecording, isFalse);
      expect(provider.isCountingDown, isFalse);
      expect(provider.lastCapturedPath, isNull);
      expect(provider.errorMessage, isNull);
      expect(provider.captureMode, CaptureMode.photo);
      expect(provider.effectName, 'NORMAL');
      expect(provider.settings.hudEnabled, isTrue);
    });

    test('clearError is a no-op when there is no error', () {
      final provider = CameraProvider();
      addTearDown(provider.dispose);

      provider.clearError();
      expect(provider.errorMessage, isNull);
    });

    test('clearLastCaptured is a no-op when nothing was captured', () {
      final provider = CameraProvider();
      addTearDown(provider.dispose);

      provider.clearLastCaptured();
      expect(provider.lastCapturedPath, isNull);
    });

    test('zoom detents fall back to the minimum when zoom is unsupported',
        () {
      final provider = CameraProvider();
      addTearDown(provider.dispose);

      // No camera initialized: min == max == 1.0, so only detent is 1x
      expect(provider.zoomDetents, [1.0]);
    });
  });
}
