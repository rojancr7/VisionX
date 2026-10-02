import 'dart:io';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/media_item.dart';

/// Service for handling media storage operations
class MediaService {
  final _uuid = const Uuid();

  static const _imageExtensions = ['.jpg', '.jpeg', '.png'];
  static const _videoExtensions = ['.mp4', '.mov'];

  /// Get the app's photo directory
  Future<Directory> getPhotoDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${appDir.path}/VisionX');
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    return photoDir;
  }

  /// Get the app's video directory
  Future<Directory> getVideoDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${appDir.path}/VisionX/Videos');
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }
    return videoDir;
  }

  /// Directory for untouched originals kept when an effect is applied at
  /// capture time. Excluded from the gallery listing (root-level scan only).
  Future<Directory> getOriginalDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/VisionX/originals');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// List all media captured by the app, newest first
  Future<List<MediaItem>> getAllMediaItems() async {
    final items = <MediaItem>[];

    final photoDir = await getPhotoDirectory();
    await for (final entity in photoDir.list()) {
      if (entity is File && _hasExtension(entity.path, _imageExtensions)) {
        final stat = await entity.stat();
        items.add(MediaItem(
          id: _uuid.v4(),
          path: entity.path,
          type: MediaType.photo,
          createdAt: stat.modified,
        ));
      }
    }

    final videoDir = await getVideoDirectory();
    await for (final entity in videoDir.list()) {
      if (entity is File && _hasExtension(entity.path, _videoExtensions)) {
        final stat = await entity.stat();
        items.add(MediaItem(
          id: _uuid.v4(),
          path: entity.path,
          type: MediaType.video,
          createdAt: stat.modified,
        ));
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  bool _hasExtension(String path, List<String> extensions) {
    final lower = path.toLowerCase();
    return extensions.any(lower.endsWith);
  }

  /// Generate unique filename for a photo
  String generatePhotoFilename() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'IMG_${timestamp}_${_uuid.v4().substring(0, 8)}.jpg';
  }

  /// Generate unique filename for a video
  String generateVideoFilename() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'VID_${timestamp}_${_uuid.v4().substring(0, 8)}.mp4';
  }

  /// Get the full path for a new photo
  Future<String> getPhotoPath() async {
    final dir = await getPhotoDirectory();
    final filename = generatePhotoFilename();
    return '${dir.path}/$filename';
  }

  /// Get the full path for a new video
  Future<String> getVideoPath() async {
    final dir = await getVideoDirectory();
    final filename = generateVideoFilename();
    return '${dir.path}/$filename';
  }

  /// Save an image to the device gallery
  Future<bool> saveImageToGallery(String imagePath) async {
    try {
      await Gal.putImage(imagePath);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Save a video to the device gallery
  Future<bool> saveVideoToGallery(String videoPath) async {
    try {
      await Gal.putVideo(videoPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a media file
  Future<bool> deleteMediaFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if a file exists
  Future<bool> fileExists(String path) async {
    return await File(path).exists();
  }

  /// Get file size in bytes
  Future<int> getFileSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }
}