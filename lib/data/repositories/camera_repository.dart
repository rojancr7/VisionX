import 'dart:async';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import '../../domain/models/camera_settings.dart';

/// Throttled frame callback for monitoring tools.
typedef MonitorFrameCallback = void Function(CameraImage image);

/// Repository for camera operations.
///
/// Wraps the `camera` plugin. Capabilities that the plugin does not expose
/// (manual ISO/shutter/WB, HDR, RAW) are surfaced through [supportedFeatures]
/// so the UI can disable them gracefully instead of crashing.
class CameraRepository {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  // Zoom level tracking (per active camera)
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  // Exposure compensation bounds (per active camera)
  double _minExposureOffset = 0.0;
  double _maxExposureOffset = 0.0;
  double _exposureStep = 0.1;

  // Monitor stream throttling
  int _frameCounter = 0;
  final int _frameSkip = 8; // deliver roughly every Nth frame
  MonitorFrameCallback? _monitorCallback;
  bool _monitoring = false;

  /// Get the camera controller
  CameraController? get controller => _controller;

  /// Check if camera is initialized
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Features the camera plugin exposes on this device. Anything absent is
  /// disabled in the UI rather than assumed.
  CameraFeatures supportedFeatures = const CameraFeatures(
    exposureOffset: false,
    focusPoint: false,
    manualIso: false,
    manualShutter: false,
    manualWhiteBalance: false,
    hdr: false,
  );

  /// All cameras (including multiple back lenses and the front camera)
  Future<List<CameraDescription>> getCameras() async {
    _cameras ??= await availableCameras();
    return _cameras!;
  }

  /// Back-facing lenses. On multi-camera phones the plugin reports each
  /// physical lens as its own [CameraDescription].
  Future<List<CameraDescription>> getBackCameras() async {
    final cameras = await getCameras();
    final back = cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .toList();
    return back.isNotEmpty ? back : cameras;
  }

  /// Initialize camera for a specific physical camera
  Future<void> initializeWithCamera(
    CameraDescription camera, {
    bool enableAudio = true,
  }) async {
    await disposeCamera();

    final controller = CameraController(
      camera,
      // Highest practical still/preview resolution; takePicture captures the
      // sensor's full still size on top of this.
      ResolutionPreset.ultraHigh,
      enableAudio: enableAudio,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
    } catch (e) {
      _controller = null;
      try {
        await controller.dispose();
      } catch (_) {
        // Controller never initialized - nothing to dispose
      }
      rethrow;
    }

    _controller = controller;
    _currentZoom = 1.0;
    _minZoom = 1.0;
    _maxZoom = 1.0;
    _resetMonitor();

    await _probeCapabilities(controller);
  }

  /// Query per-camera capabilities; every probe is individually guarded so a
  /// missing capability never fails initialization.
  Future<void> _probeCapabilities(CameraController controller) async {
    try {
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
    } catch (_) {
      _minZoom = 1.0;
      _maxZoom = 1.0;
    }

    var exposureOffsetOk = false;
    try {
      _minExposureOffset = await controller.getMinExposureOffset();
      _maxExposureOffset = await controller.getMaxExposureOffset();
      _exposureStep = await controller.getExposureOffsetStepSize();
      if (_exposureStep <= 0) _exposureStep = 0.1;
      exposureOffsetOk = _maxExposureOffset > _minExposureOffset;
    } catch (_) {
      _minExposureOffset = 0.0;
      _maxExposureOffset = 0.0;
      _exposureStep = 0.1;
    }

    var focusPointOk = false;
    try {
      // Probing with the center point; a failure means unsupported.
      await controller.setFocusPoint(const Offset(0.5, 0.5));
      focusPointOk = true;
    } catch (_) {
      focusPointOk = false;
    }

    supportedFeatures = CameraFeatures(
      exposureOffset: exposureOffsetOk,
      focusPoint: focusPointOk,
      zoom: _maxZoom > _minZoom,
      flash: !isFrontCamera,
      // The camera plugin does not expose these APIs at all:
      manualIso: false,
      manualShutter: false,
      manualWhiteBalance: false,
      hdr: false,
    );
  }

  /// Apply camera settings after (re)initialization
  Future<void> applySettings(CameraSettings settings) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.setFlashMode(settings.flashMode);
    } catch (_) {
      // Flash not available on this camera
    }

    if (supportedFeatures.zoom) {
      final zoom = settings.zoomLevel.clamp(_minZoom, _maxZoom).toDouble();
      try {
        await controller.setZoomLevel(zoom);
        _currentZoom = zoom;
      } catch (_) {
        // Zoom not available on this camera
      }
    }
  }

  // ---- Zoom ----

  double get minZoomLevel => _minZoom;
  double get maxZoomLevel => _maxZoom;
  double get currentZoomLevel => _currentZoom;

  Future<void> setZoomLevel(double zoom) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_maxZoom <= _minZoom) return;

    final clamped = zoom.clamp(_minZoom, _maxZoom).toDouble();
    try {
      await controller.setZoomLevel(clamped);
      _currentZoom = clamped;
    } catch (_) {
      // Zoom not available on this camera
    }
  }

  // ---- Exposure compensation ----

  double get minExposureOffset => _minExposureOffset;
  double get maxExposureOffset => _maxExposureOffset;
  double get exposureStep => _exposureStep;

  /// Returns the actually-applied offset (quantized by the device step).
  Future<double> setExposureOffset(double offset) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return 0.0;
    if (!supportedFeatures.exposureOffset) return 0.0;

    final clamped = offset.clamp(_minExposureOffset, _maxExposureOffset);
    final stepped = (clamped / _exposureStep).roundToDouble() * _exposureStep;
    try {
      final applied = await controller.setExposureOffset(stepped);
      return applied;
    } catch (_) {
      return 0.0;
    }
  }

  // ---- Focus / exposure points ----

  Future<void> setFocusPoint(Offset point) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!supportedFeatures.focusPoint) return;
    try {
      await controller.setFocusPoint(point);
    } catch (_) {
      // Focus point not supported
    }
  }

  Future<void> setExposurePoint(Offset? point) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!supportedFeatures.focusPoint) return;
    try {
      await controller.setExposurePoint(point);
    } catch (_) {
      // Exposure point not supported
    }
  }

  Future<void> setFocusMode(FocusMode mode) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFocusMode(mode);
    } catch (_) {
      // Focus mode not supported
    }
  }

  // ---- Flash ----

  Future<void> setFlashMode(FlashMode mode) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(mode);
    } catch (_) {
      // Flash not available on this camera
    }
  }

  // ---- Monitoring frame stream ----

  bool get isMonitoring => _monitoring;

  /// Start delivering throttled low-rate frames to [callback] for the
  /// histogram/zebra/exposure-meter tools. Frames are skipped aggressively
  /// (1 in [_frameSkip]) so monitoring costs almost nothing.
  Future<bool> startMonitorStream(MonitorFrameCallback callback) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return false;
    if (controller.value.isRecordingVideo) return false;
    if (_monitoring) {
      _monitorCallback = callback;
      return true;
    }

    try {
      _monitorCallback = callback;
      _frameCounter = 0;
      await controller.startImageStream(_onFrame);
      _monitoring = true;
      return true;
    } catch (_) {
      _monitoring = false;
      _monitorCallback = null;
      return false;
    }
  }

  void _onFrame(CameraImage image) {
    _frameCounter = (_frameCounter + 1) % _frameSkip;
    if (_frameCounter != 0) return;
    final callback = _monitorCallback;
    if (callback != null) callback(image);
  }

  Future<void> stopMonitorStream() async {
    _monitorCallback = null;
    if (!_monitoring) return;
    try {
      await _controller?.stopImageStream();
    } catch (_) {
      // Stream already stopped
    }
    _monitoring = false;
  }

  void _resetMonitor() {
    _monitorCallback = null;
    _monitoring = false;
    _frameCounter = 0;
  }

  // ---- Capture ----

  /// Capture a photo. Returns null if capture failed.
  Future<XFile?> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    if (controller.value.isRecordingVideo) return null;
    if (controller.value.isTakingPicture) return null;

    try {
      return await controller.takePicture();
    } catch (_) {
      return null;
    }
  }

  /// Start video recording. Throws if the camera cannot record.
  Future<void> startVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw CameraException('notInitialized', 'Camera is not initialized');
    }
    if (controller.value.isRecordingVideo) return;

    // Image streaming and recording cannot run simultaneously.
    await stopMonitorStream();
    await controller.startVideoRecording();
  }

  /// Stop video recording. Returns null if no active recording or stop failed.
  Future<XFile?> stopVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) return null;

    try {
      return await controller.stopVideoRecording();
    } catch (_) {
      return null;
    }
  }

  /// Check if currently recording video
  bool get isRecordingVideo => _controller?.value.isRecordingVideo ?? false;

  /// Flash is generally only available on the back camera
  bool get isFlashAvailable => !isFrontCamera;

  /// Check if front camera is being used
  bool get isFrontCamera =>
      _controller?.description.lensDirection == CameraLensDirection.front;

  /// Dispose camera resources
  Future<void> disposeCamera() async {
    await stopMonitorStream();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {
        // Controller already disposed or never fully initialized
      }
    }
  }
}

/// Capability flags detected at initialization time.
class CameraFeatures {
  final bool zoom;
  final bool exposureOffset;
  final bool focusPoint;
  final bool flash;
  final bool manualIso;
  final bool manualShutter;
  final bool manualWhiteBalance;
  final bool hdr;

  const CameraFeatures({
    this.zoom = false,
    this.exposureOffset = false,
    this.focusPoint = false,
    this.flash = false,
    this.manualIso = false,
    this.manualShutter = false,
    this.manualWhiteBalance = false,
    this.hdr = false,
  });
}
