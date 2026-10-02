import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/services/media_service.dart';
import '../../domain/models/media_item.dart';
import 'media_viewer_screen.dart';

/// Grid gallery of media captured by the app
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final MediaService _mediaService = MediaService();
  List<MediaItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final items = await _mediaService.getAllMediaItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load media');
    }
  }

  Future<void> _openViewer(MediaItem item) async {
    // Reload on return - the viewer may have deleted the item
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MediaViewerScreen(item: item)),
    );
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Gallery'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final items = _items;

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadItems,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (items == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No photos or videos yet.\nCapture something with the camera!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadItems,
      color: Colors.tealAccent,
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return _MediaTile(
            item: items[index],
            onTap: () => _openViewer(items[index]),
          );
        },
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const _MediaTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, HH:mm');

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.type == MediaType.photo)
            Image.file(
              File(item.path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Colors.grey.shade900,
                child: const Icon(Icons.broken_image,
                    color: Colors.white30, size: 32),
              ),
            )
          else
            Container(
              color: Colors.grey.shade900,
              child: const Center(
                child: Icon(Icons.videocam, color: Colors.white30, size: 32),
              ),
            ),
          if (item.type == MediaType.video)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: Text(
              dateFormat.format(item.createdAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
