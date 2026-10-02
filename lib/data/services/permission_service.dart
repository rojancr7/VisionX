import 'package:permission_handler/permission_handler.dart';

/// Service for handling runtime permissions
class PermissionService {
  /// Request camera permission
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Request microphone permission for video recording
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Request storage permissions
  Future<bool> requestStoragePermission() async {
    // For Android 13+, we need specific media permissions
    if (await Permission.photos.request().isGranted ||
        await Permission.videos.request().isGranted) {
      return true;
    }

    // For older Android versions
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// Request all required permissions
  Future<Map<Permission, PermissionStatus>> requestAllPermissions() async {
    return await [
      Permission.camera,
      Permission.microphone,
      Permission.photos,
      Permission.videos,
    ].request();
  }

  /// Check if camera permission is granted
  Future<bool> hasCameraPermission() async {
    return await Permission.camera.isGranted;
  }

  /// Check if microphone permission is granted
  Future<bool> hasMicrophonePermission() async {
    return await Permission.microphone.isGranted;
  }

  /// Check if storage permissions are granted
  Future<bool> hasStoragePermission() async {
    return await Permission.photos.isGranted ||
        await Permission.videos.isGranted ||
        await Permission.storage.isGranted;
  }

  /// Open app settings
  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}