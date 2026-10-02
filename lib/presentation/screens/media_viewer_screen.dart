import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../domain/models/media_item.dart';
import '../../data/services/media_service.dart';

/// Full-screen viewer for a captured photo or video
class MediaViewerScreen extends StatefulWidget {
  final MediaItem item;

  const MediaViewerScreen({super.key, required this.item});

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  final MediaService _mediaService = MediaService();
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.item.type == MediaType.video) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.file(File(widget.item.path));
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.play();
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play this video')),
        );
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Delete?'),
        content: Text(
          widget.item.type == MediaType.video
              ? 'This video will be permanently deleted.'
              : 'This photo will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok = await _mediaService.deleteMediaFile(widget.item.path);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete file')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          widget.item.type == MediaType.video ? 'Video' : 'Photo',
        ),
        actions: [
          IconButton(
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Center(
        child: widget.item.type == MediaType.video
            ? _buildVideoBody()
            : _buildPhotoBody(),
      ),
    );
  }

  Widget _buildPhotoBody() {
    return InteractiveViewer(
      maxScale: 5,
      child: Center(
        child: Image.file(
          File(widget.item.path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image,
            color: Colors.white30,
            size: 64,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoBody() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Loading video...',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        const SizedBox(height: 16),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: Colors.tealAccent,
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      value.isPlaying
                          ? controller.pause()
                          : controller.play();
                    });
                  },
                  icon: Icon(
                    value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                Text(
                  '${_format(value.position)} / ${_format(value.duration)}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
