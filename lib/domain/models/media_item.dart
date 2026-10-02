/// Represents a captured media item (photo or video)
class MediaItem {
  final String id;
  final String path;
  final MediaType type;
  final DateTime createdAt;
  final int? duration; // For videos, in seconds

  MediaItem({
    required this.id,
    required this.path,
    required this.type,
    required this.createdAt,
    this.duration,
  });
}

enum MediaType {
  photo,
  video,
}