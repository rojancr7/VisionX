import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/services/media_service.dart';
import '../../domain/models/media_item.dart';
import 'photo_editor_screen.dart';

/// Capture review screen (Phase 8).
///
/// Shows the photo right after capture with EDIT / SAVE / SHARE / DELETE /
/// RETAKE actions. The photo has already been saved to the gallery at
/// capture time; SAVE re-offers the save when that background step failed.
class PhotoPreviewScreen extends StatefulWidget {
  final MediaItem item;

  const PhotoPreviewScreen({super.key, required this.item});

  @override
  State<PhotoPreviewScreen> createState() => _PhotoPreviewScreenState();
}

class _PhotoPreviewScreenState extends State<PhotoPreviewScreen> {
  final MediaService _mediaService = MediaService();

  late String _path;
  bool _savedToGallery = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _path = widget.item.path;
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(_path)], text: 'Captured with VisionX'),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet')),
      );
    }
  }

  Future<void> _saveToGallery() async {
    setState(() => _busy = true);
    final ok = await _mediaService.saveImageToGallery(_path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _savedToGallery = ok;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Saved to gallery' : 'Could not save to gallery'),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Delete photo?'),
        content: const Text('This photo will be permanently deleted.'),
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

    setState(() => _busy = true);
    final ok = await _mediaService.deleteMediaFile(_path);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete photo')),
      );
    }
  }

  Future<void> _edit() async {
    final exportedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PhotoEditorScreen(
          item: MediaItem(
            id: widget.item.id,
            path: _path,
            type: MediaType.photo,
            createdAt: widget.item.createdAt,
          ),
        ),
      ),
    );

    if (exportedPath != null && mounted) {
      setState(() {
        _path = exportedPath;
        _savedToGallery = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Preview'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.file(
                File(_path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image,
                  color: Colors.white30,
                  size: 64,
                ),
              ),
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: Icons.delete_outline,
                label: 'DELETE',
                onTap: _delete,
              ),
              _ActionButton(
                icon: Icons.auto_fix_high_outlined,
                label: 'EDIT',
                onTap: _busy ? null : _edit,
              ),
              _ActionButton(
                icon: Icons.ios_share,
                label: 'SHARE',
                onTap: _busy ? null : _share,
              ),
              _ActionButton(
                icon: _savedToGallery ? Icons.check : Icons.save_outlined,
                label: _savedToGallery ? 'SAVED' : 'SAVE',
                onTap: _busy ? null : _saveToGallery,
              ),
              _ActionButton(
                icon: Icons.camera_alt_outlined,
                label: 'RETAKE',
                onTap: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
