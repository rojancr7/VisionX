import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../data/repositories/camera_repository.dart';
import '../../data/services/frame_analyzer_service.dart';
import '../../data/services/media_service.dart';
import '../../data/services/permission_service.dart';
import '../../domain/models/camera_settings.dart';
import '../../domain/models/effect_preset.dart';
import '../../domain/models/media_item.dart';
import '../editor/image_processor.dart';

enum CaptureMode {
  photo,
  video,
}

enum CameraState {
  initializing,
  ready,
  capturing,
  recording,
  error,
}

class CameraProvider extends ChangeNotifier {
  final CameraRepository _cameraRepo = CameraRepository();
  final MediaService _mediaService = MediaService();
  final PermissionService _permissionService = PermissionService();

  // State
  CameraState _state = CameraState.initializing;
  CaptureMode _captureMode = CaptureMode.photo;
  CameraSettings _settings = const CameraSettings();
  String? _lastCapturedPath;
  MediaType? _lastCapturedType;
  String? _errorMessage;
  bool _hasAudioPermission = false;
  bool _isPaused = false;

  // Recording state
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  bool _isRecording = false;

  // Timer for self-timer feature
  Timer? _countdownTimer;
  int _countdownValue = 0;

  // Lenses (physical back cameras reported by the plugin)
  List<CameraDescription> _backLenses = [];
  List<double> _lensBaseFactors = const [1.0];
  int _lensIndex = 0;
  bool _usingFrontCamera = false;

  // Focus / exposure
  Offset? _focusPoint;
  bool _focusLocked = false;
  bool _showReticle = false;
  Timer? _reticleTimer;
  double _appliedExposureOffset = 0.0;

  // Monitoring
  FrameStats? _frameStats;
  DateTime _lastFrameNotify = DateTime.fromMillisecondsSinceEpoch(0);
  double _rollDegrees = 0.0;
  DateTime _lastSensorUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<AccelerometerEvent>? _sensorSub;

  // Panels
  bool _effectsPanelOpen = false;
  bool _manualPanelOpen = false;

  /// Called after a successful photo capture so the screen can push the
  /// preview (EDIT / SAVE / SHARE / DELETE / RETAKE).
  void Function(MediaItem item)? onPhotoCaptured;

  // Getters
  CameraController? get controller => _cameraRepo.controller;
  CameraState get state => _state;
  CaptureMode get captureMode => _captureMode;
  CameraSettings get settings => _settings;
  String? get lastCapturedPath => _lastCapturedPath;
  MediaType? get lastCapturedType => _lastCapturedType;
  String? get errorMessage => _errorMessage;
  bool get isRecording => _isRecording;
  int get recordingDuration => _recordingDuration;
  int get countdownValue => _countdownValue;
  bool get isCountingDown => _countdownTimer != null;
  bool get isBusy =>
      _state == CameraState.capturing || _state == CameraState.initializing;
  bool get effectsPanelOpen => _effectsPanelOpen;
  bool get manualPanelOpen => _manualPanelOpen;

  // Lens / zoom getters
  List<CameraDescription> get backLenses => _backLenses;
  List<double> get lensBaseFactors => _lensBaseFactors;
  int get lensIndex => _lensIndex;
  bool get isFrontCamera => _usingFrontCamera;
  int get lensCount => _usingFrontCamera ? 1 : _backLenses.length;

  /// Displayed zoom factor (lens base factor x per-lens zoom)
  double get zoomFactor =>
      _currentLensBase * _cameraRepo.currentZoomLevel;
  double get minZoomFactor =>
      _currentLensBase * _cameraRepo.minZoomLevel;
  double get maxZoomFactor =>
      _currentLensBase * _cameraRepo.maxZoomLevel;
  double get _currentLensBase =>
      _usingFrontCamera ? 1.0 : (_lensIndex < _lensBaseFactors.length
          ? _lensBaseFactors[_lensIndex]
          : 1.0);

  /// Detent stops for the zoom wheel, limited to what the device supports
  List<double> get zoomDetents {
    const candidates = [0.6, 1.0, 2.0, 5.0, 10.0];
    final min = minZoomFactor;
    final max = math.max(maxZoomFactor, min);
    final detents =
        candidates.where((c) => c >= min - 0.001 && c <= max + 0.001).toList();
    if (detents.isEmpty) detents.add(min);
    if (!detents.contains(1.0) && 1.0 >= min && 1.0 <= max) {
      detents.add(1.0);
      detents.sort();
    }
    return detents;
  }

  // Exposure getters
  double get exposureOffset => _appliedExposureOffset;
  double get minExposureOffset => _cameraRepo.minExposureOffset;
  double get maxExposureOffset => _cameraRepo.maxExposureOffset;
  double get exposureStep => _cameraRepo.exposureStep;

  // Focus getters
  Offset? get focusPoint => _focusPoint;
  bool get focusLocked => _focusLocked;
  bool get showReticle => _showReticle;

  // Monitoring getters
  FrameStats? get frameStats => _frameStats;
  double get rollDegrees => _rollDegrees;
  CameraFeatures get features => _cameraRepo.supportedFeatures;

  // Zoom compat getters (used by simple UI fallbacks)
  double get minZoom => _cameraRepo.minZoomLevel;
  double get maxZoom => _cameraRepo.maxZoomLevel;
  double get currentZoom => _cameraRepo.currentZoomLevel;
  bool get isFlashAvailable => _cameraRepo.isFlashAvailable;
  bool get isInitialized => _state == CameraState.ready;

  // ---- HUD ----

  String get resolutionLabel => '4K';
  String get zoomLabel => '${zoomFactor.toStringAsFixed(1)}x';
  String get evLabel {
    final v = _appliedExposureOffset;
    final sign = v > 0 ? '+' : '';
    return 'EV $sign${v.toStringAsFixed(1)}';
  }

  String get effectName => EffectPresets.at(_settings.effectIndex).name;

  bool get isMonitoringActive =>
      _settings.histogramEnabled ||
      _settings.zebraEnabled ||
      _settings.highlightWarningEnabled ||
      _settings.exposureMeterEnabled;

  /// Initialize camera
  Future<void> initializeCamera() async {
    if (_isRecording) return;

    _cancelCountdown();
    _state = CameraState.initializing;
    notifyListeners();

    try {
      final hasCamera = await _permissionService.requestCameraPermission();
      if (!hasCamera) {
        _state = CameraState.error;
        _errorMessage =
            'Camera permission denied. Grant camera access in Settings to use VisionX.';
        notifyListeners();
        return;
      }

      _hasAudioPermission =
          await _permissionService.requestMicrophonePermission();

      await _initCurrentCamera();

      _errorMessage = null;
      _state = CameraState.ready;
    } catch (e) {
      _state = CameraState.error;
      _errorMessage = 'Failed to initialize camera: $e';
    }

    _syncMonitoring();
    notifyListeners();
  }

  /// Resolve and initialize whichever camera is currently selected
  /// (front camera, or back lens at [_lensIndex]).
  Future<void> _initCurrentCamera() async {
    final cameras = await _cameraRepo.getCameras();
    if (cameras.isEmpty) {
      throw CameraException('noCameras', 'No cameras available on this device');
    }

    if (_usingFrontCamera) {
      final front = cameras
          .where((c) => c.lensDirection == CameraLensDirection.front)
          .toList();
      if (front.isEmpty) throw CameraException('noFront', 'No front camera');
      await _initLens(front.first);
      return;
    }

    _backLenses = await _cameraRepo.getBackCameras();
    _lensBaseFactors = _computeLensBases(_backLenses);
    _lensIndex = _lensIndex.clamp(0, _backLenses.length - 1);
    await _initLens(_backLenses[_lensIndex]);
  }

  /// Initialize with a specific camera description
  Future<void> _initLens(CameraDescription camera) async {
    await _cameraRepo.initializeWithCamera(camera, enableAudio: _hasAudioPermission);

    // Zoom settings are relative to the new lens - reset to native 1x
    _settings = _settings.copyWith(zoomLevel: 1.0);
    _appliedExposureOffset = 0.0;
    _focusLocked = false;
    _focusPoint = null;

    await _cameraRepo.applySettings(_settings);
  }

  /// Derive display base factors (0.6x / 1x / 2x ...) for the back lenses.
  ///
  /// The camera plugin does not expose focal lengths, so labels use name
  /// hints when available and fall back to sequential numbering. Switching
  /// between these chips always performs a REAL physical camera switch.
  List<double> _computeLensBases(List<CameraDescription> lenses) {
    if (lenses.length <= 1) return const [1.0];

    final bases = List<double>.filled(lenses.length, 1.0);
    var unnamedSlot = 1;
    for (var i = 0; i < lenses.length; i++) {
      final name = lenses[i].name.toLowerCase();
      if (name.contains('ultra') || name.contains('0.6') || name.contains('0,6')) {
        bases[i] = 0.6;
      } else if (name.contains('tele')) {
        bases[i] = 2.0;
      } else if (name.contains('wide') || name.contains('main') || name.contains('rear')) {
        bases[i] = 1.0;
      } else {
        bases[i] = unnamedSlot.toDouble();
        unnamedSlot++;
      }
    }

    // Resolve duplicates (two "2.0" lenses) by bumping the later one
    final seen = <double>{};
    for (var i = 0; i < bases.length; i++) {
      var b = bases[i];
      while (seen.contains(b)) {
        b += 1.0;
      }
      bases[i] = b;
      seen.add(b);
    }
    return bases;
  }

  /// Select a physical back lens by index
  Future<void> selectLens(int index) async {
    if (_state != CameraState.ready || _isRecording || isCountingDown) return;
    if (_usingFrontCamera) return;
    if (index < 0 || index >= _backLenses.length || index == _lensIndex) return;

    _lensIndex = index;
    _state = CameraState.initializing;
    _hidePanels();
    notifyListeners();

    try {
      await _initLens(_backLenses[index]);
      _errorMessage = null;
      _state = CameraState.ready;
    } catch (e) {
      _errorMessage = 'Failed to switch lens';
      _state = CameraState.error;
    }

    _syncMonitoring();
    notifyListeners();
  }

  /// Switch between front and back cameras
  Future<void> switchCamera() async {
    if (_state != CameraState.ready || _isRecording || isCountingDown) return;

    _state = CameraState.initializing;
    _hidePanels();
    notifyListeners();

    try {
      if (_usingFrontCamera) {
        _usingFrontCamera = false;
        await _initCurrentCamera();
      } else {
        final cameras = await _cameraRepo.getCameras();
        final front = cameras
            .where((c) => c.lensDirection == CameraLensDirection.front)
            .toList();
        if (front.isEmpty) {
          _errorMessage = 'This device has no front camera';
          _state = CameraState.ready;
          notifyListeners();
          return;
        }
        _usingFrontCamera = true;
        await _initLens(front.first);
      }
      _errorMessage = null;
      _state = CameraState.ready;
    } catch (e) {
      _errorMessage = 'Failed to switch camera';
      _state = CameraState.error;
    }

    _syncMonitoring();
    notifyListeners();
  }

  // ---- Zoom ----

  /// Set the displayed zoom factor (e.g. 1.0, 2.4). Clamped to the active
  /// lens range; performs no fake lens switching.
  Future<void> setZoomFactor(double displayFactor) async {
    if (_state != CameraState.ready || _isRecording) return;
    final controllerZoom = (displayFactor / _currentLensBase)
        .clamp(_cameraRepo.minZoomLevel, _cameraRepo.maxZoomLevel)
        .toDouble();
    await _cameraRepo.setZoomLevel(controllerZoom);
    _settings = _settings.copyWith(zoomLevel: controllerZoom);
    notifyListeners();
  }

  /// Quick return to native 1x
  Future<void> resetZoom() => setZoomFactor(_currentLensBase);

  // ---- Exposure ----

  Future<void> setExposureOffsetEv(double ev) async {
    if (_state != CameraState.ready) return;
    final applied = await _cameraRepo.setExposureOffset(ev);
    _appliedExposureOffset = applied;
    _settings = _settings.copyWith(exposureOffset: applied);
    notifyListeners();
  }

  Future<void> resetExposureOffset() => setExposureOffsetEv(0.0);

  // ---- Focus ----

  /// Tap-to-focus with a normalized preview point (0..1)
  Future<void> tapToFocus(Offset normalizedPoint) async {
    if (_state != CameraState.ready || _isRecording) return;

    _focusPoint = normalizedPoint;
    _showReticle = true;
    notifyListeners();

    await _cameraRepo.setExposurePoint(normalizedPoint);
    await _cameraRepo.setFocusPoint(normalizedPoint);

    if (!_focusLocked) {
      _reticleTimer?.cancel();
      _reticleTimer = Timer(const Duration(milliseconds: 2500), () {
        _showReticle = false;
        notifyListeners();
      });
    }
  }

  /// Hold-to-lock focus (AF). Exposure follows the locked focus point.
  Future<void> toggleFocusLock() async {
    if (_state != CameraState.ready || _isRecording) return;

    if (_focusLocked) {
      _focusLocked = false;
      await _cameraRepo.setFocusMode(FocusMode.auto);
      _showReticle = false;
    } else {
      _focusLocked = true;
      _showReticle = true;
      _reticleTimer?.cancel();
      await _cameraRepo.setFocusMode(FocusMode.locked);
    }
    notifyListeners();
  }

  // ---- Flash ----

  Future<void> cycleFlashMode() async {
    if (_state != CameraState.ready) return;
    if (_usingFrontCamera) return;

    FlashMode newMode;
    switch (_settings.flashMode) {
      case FlashMode.off:
        newMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        newMode = FlashMode.always;
        break;
      case FlashMode.always:
        newMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        newMode = FlashMode.off;
        break;
    }

    _settings = _settings.copyWith(flashMode: newMode);
    await _cameraRepo.setFlashMode(newMode);
    notifyListeners();
  }

  // ---- UI toggles ----

  void setCaptureMode(CaptureMode mode) {
    if (_isRecording || isCountingDown) return;
    if (_captureMode == mode) return;
    _captureMode = mode;
    notifyListeners();
  }

  void setTimer(int? seconds) {
    if (_isRecording || isCountingDown) return;
    _settings = _settings.copyWith(timerSeconds: seconds);
    notifyListeners();
  }

  void toggleGrid() =>
      _settings = _settings.copyWith(gridEnabled: !_settings.gridEnabled);
  void toggleLevel() {
    _settings = _settings.copyWith(levelEnabled: !_settings.levelEnabled);
    _syncLevelSensor();
  }
  void toggleHud() =>
      _settings = _settings.copyWith(hudEnabled: !_settings.hudEnabled);
  void toggleHistogram() {
    _settings =
        _settings.copyWith(histogramEnabled: !_settings.histogramEnabled);
    _syncMonitoring();
  }
  void toggleZebra() {
    _settings = _settings.copyWith(zebraEnabled: !_settings.zebraEnabled);
    _syncMonitoring();
  }
  void toggleHighlightWarning() {
    _settings = _settings.copyWith(
        highlightWarningEnabled: !_settings.highlightWarningEnabled);
    _syncMonitoring();
  }
  void toggleExposureMeter() {
    _settings =
        _settings.copyWith(exposureMeterEnabled: !_settings.exposureMeterEnabled);
    _syncMonitoring();
  }

  void setEffect(int index) {
    _settings = _settings.copyWith(effectIndex: index);
  }

  void setEffectsPanelOpen(bool open) {
    _effectsPanelOpen = open;
    notifyListeners();
  }

  void setManualPanelOpen(bool open) {
    _manualPanelOpen = open;
    notifyListeners();
  }

  void _hidePanels() {
    _effectsPanelOpen = false;
    _manualPanelOpen = false;
  }

  // ---- Monitoring plumbing ----

  void _syncMonitoring() {
    if (isMonitoringActive &&
        _state == CameraState.ready &&
        !_isRecording &&
        !_isPaused) {
      _cameraRepo.startMonitorStream(_onMonitorFrame);
    } else {
      _cameraRepo.stopMonitorStream();
      if (!isMonitoringActive) _frameStats = null;
    }
  }

  void _onMonitorFrame(CameraImage image) {
    try {
      final stats = analyzeFrame(image);
      _frameStats = stats;
      // Throttle UI updates - monitoring runs at a low rate but the frame
      // callback still fires faster than the UI needs.
      final now = DateTime.now();
      if (now.difference(_lastFrameNotify).inMilliseconds >= 200) {
        _lastFrameNotify = now;
        notifyListeners();
      }
    } catch (_) {
      // A bad frame must never take down the preview
    }
  }

  void _syncLevelSensor() {
    if (_settings.levelEnabled) {
      _sensorSub ??= accelerometerEventStream().listen((event) {
        final now = DateTime.now();
        if (now.difference(_lastSensorUpdate).inMilliseconds < 100) return;
        _lastSensorUpdate = now;
        // Screen-plane tilt from the gravity projection.
        _rollDegrees = math.atan2(event.x, event.y) * 180.0 / math.pi;
        notifyListeners();
      }, onError: (_) {
        // Sensor unavailable - level stays at zero
      });
    } else {
      _sensorSub?.cancel();
      _sensorSub = null;
    }
  }

  // ---- Capture ----

  Future<void> capture() async {
    if (_state != CameraState.ready) return;
    if (isCountingDown) return;

    // Handle self-timer countdown
    if (_settings.timerSeconds != null && _settings.timerSeconds! > 0) {
      _startCountdown();
      return;
    }

    if (_captureMode == CaptureMode.photo) {
      await _takePhoto();
    } else {
      await _toggleVideoRecording();
    }
  }

  void _startCountdown() {
    _cancelCountdown();
    _countdownValue = _settings.timerSeconds ?? 3;
    notifyListeners();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdownValue--;
      notifyListeners();

      if (_countdownValue <= 0) {
        timer.cancel();
        _countdownTimer = null;
        _countdownValue = 0;
        if (_captureMode == CaptureMode.photo) {
          _takePhoto();
        } else {
          _toggleVideoRecording();
        }
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownValue = 0;
  }

  /// Take a photo. When an effect is selected the original is preserved in
  /// the originals/ folder and the processed version is the saved deliverable.
  Future<void> _takePhoto() async {
    _state = CameraState.capturing;
    notifyListeners();

    try {
      final file = await _cameraRepo.takePicture();
      if (file != null) {
        final originalBytes = await io.File(file.path).readAsBytes();
        final effect = EffectPresets.at(_settings.effectIndex);

        var finalBytes = originalBytes;
        io.Directory? originalsDir;
        if (effect != EffectPresets.normal) {
          try {
            finalBytes = await ImageProcessor.applyEffect(originalBytes, effect);
            originalsDir = await _mediaService.getOriginalDirectory();
          } catch (_) {
            // Processing failed - save the unprocessed capture instead
            finalBytes = originalBytes;
            originalsDir = null;
          }
        }

        final savePath = await _mediaService.getPhotoPath();
        await io.File(savePath).writeAsBytes(finalBytes);

        // Keep the untouched original alongside (root scan ignores this dir)
        if (originalsDir != null) {
          try {
            final name = savePath.split('/').last;
            await io.File('${originalsDir.path}/$name')
                .writeAsBytes(originalBytes);
          } catch (_) {
            // Original backup is best-effort
          }
        }

        final saved = await _mediaService.saveImageToGallery(savePath);
        if (!saved) {
          _errorMessage = 'Photo captured, but could not be saved to gallery';
        }

        _lastCapturedPath = savePath;
        _lastCapturedType = MediaType.photo;
        onPhotoCaptured?.call(
          MediaItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            path: savePath,
            type: MediaType.photo,
            createdAt: DateTime.now(),
          ),
        );
      } else {
        _errorMessage = 'Failed to capture photo';
      }

      _state = CameraState.ready;
    } catch (e) {
      _errorMessage = 'Failed to capture photo: $e';
      _state = CameraState.ready;
    }

    notifyListeners();
  }

  Future<void> _toggleVideoRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    _state = CameraState.recording;
    _isRecording = true;
    _recordingDuration = 0;
    _hidePanels();
    notifyListeners();

    try {
      await _cameraRepo.startVideoRecording();

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingDuration++;
        notifyListeners();
      });
    } catch (e) {
      _errorMessage = 'Failed to start recording';
      _isRecording = false;
      _recordingDuration = 0;
      _state = CameraState.ready;
    }

    notifyListeners();
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _state = CameraState.capturing;
    notifyListeners();

    try {
      final file = await _cameraRepo.stopVideoRecording();
      if (file != null) {
        final savePath = await _mediaService.getVideoPath();
        await io.File(file.path).copy(savePath);

        final saved = await _mediaService.saveVideoToGallery(savePath);
        if (!saved) {
          _errorMessage = 'Video saved to app storage, but not to gallery';
        }

        _lastCapturedPath = savePath;
        _lastCapturedType = MediaType.video;
      } else {
        _errorMessage = 'Failed to save recording';
      }

      _isRecording = false;
      _recordingDuration = 0;
      _state = CameraState.ready;
    } catch (e) {
      _errorMessage = 'Failed to stop recording: $e';
      _isRecording = false;
      _recordingDuration = 0;
      _state = CameraState.ready;
    }

    _syncMonitoring();
    notifyListeners();
  }

  /// Release the camera when the app moves to the background
  Future<void> pauseCamera() async {
    if (_state != CameraState.ready && _state != CameraState.recording) return;
    if (isCountingDown) _cancelCountdown();
    if (_isRecording) await _stopRecording();
    _isPaused = true;
    _hidePanels();
    _sensorSub?.pause();
    _state = CameraState.initializing;
    await _cameraRepo.disposeCamera();
    notifyListeners();
  }

  /// Re-initialize the camera when the app comes back to the foreground
  Future<void> resumeCamera() async {
    if (!_isPaused) return;
    _isPaused = false;
    _sensorSub?.resume();
    await initializeCamera();
  }

  /// Clear the current error message
  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Forget the last captured media (e.g. after the user deleted it in the
  /// capture preview)
  void clearLastCaptured() {
    if (_lastCapturedPath == null && _lastCapturedType == null) return;
    _lastCapturedPath = null;
    _lastCapturedType = null;
    notifyListeners();
  }

  String get formattedDuration {
    final minutes = _recordingDuration ~/ 60;
    final seconds = _recordingDuration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _cancelCountdown();
    _reticleTimer?.cancel();
    _recordingTimer?.cancel();
    _sensorSub?.cancel();
    _cameraRepo.disposeCamera();
    super.dispose();
  }
}
