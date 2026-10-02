import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/services/media_service.dart';
import '../../domain/models/edit_parameters.dart';
import '../../domain/models/effect_preset.dart';
import '../../domain/models/media_item.dart';
import '../editor/image_processor.dart';

/// VisionX photo editor (Phase 9).
///
/// Non-destructive by design:
///   Original photo (never modified)
///     -> EditParameters
///     -> live preview (ColorFilter + shaders)
///     -> exported copy ("_edit.jpg") written on DONE.
class PhotoEditorScreen extends StatefulWidget {
  final MediaItem item;

  const PhotoEditorScreen({super.key, required this.item});

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final MediaService _mediaService = MediaService();
  final EditHistory _history = EditHistory();

  Uint8List? _previewBytes;
  bool _showAfter = true;
  int _tab = 0;
  bool _exporting = false;

  EditParameters get _params => _history.current;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final bytes = await File(widget.item.path).readAsBytes();
      if (!mounted) return;
      setState(() => _previewBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load photo for editing')),
      );
      Navigator.of(context).pop();
    }
  }

  void _update(EditParameters next) {
    setState(() => _history.push(next));
  }

  Future<void> _export() async {
    if (_previewBytes == null) return;

    // Identity edits: nothing to bake, just hand back the original path.
    if (_params.isIdentity) {
      Navigator.of(context).pop(widget.item.path);
      return;
    }

    setState(() => _exporting = true);
    try {
      final sourceBytes = await File(widget.item.path).readAsBytes();
      final exported = await ImageProcessor.exportEdited(sourceBytes, _params);

      final dir = await _mediaService.getPhotoDirectory();
      final base = widget.item.path.split('/').last.replaceAll('.jpg', '');
      final exportPath = '${dir.path}/${base}_edit.jpg';
      await File(exportPath).writeAsBytes(exported);

      // Exported copies also go to the gallery
      await _mediaService.saveImageToGallery(exportPath);

      if (!mounted) return;
      Navigator.of(context).pop(exportPath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export failed - try fewer adjustments or a smaller '
              'photo'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('VisionX Editor'),
        actions: [
          // BEFORE | AFTER toggle
          TextButton(
            onPressed: () => setState(() => _showAfter = !_showAfter),
            child: Text(
              _showAfter ? 'AFTER' : 'BEFORE',
              style: const TextStyle(
                color: Colors.tealAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            onPressed: _history.canUndo
                ? () => setState(() => _history.undo())
                : null,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: _history.canRedo
                ? () => setState(() => _history.redo())
                : null,
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
          ),
          IconButton(
            onPressed: !_params.isIdentity
                ? () => setState(() => _history.clear())
                : null,
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset all edits',
          ),
        ],
      ),
      body: _exporting
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.tealAccent),
                  SizedBox(height: 16),
                  Text(
                    'Exporting full-resolution photo...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(child: _buildCanvas()),
                _buildTabBar(),
                _buildControls(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _params.isIdentity
                      ? 'Original photo - no edits'
                      : 'Original is kept untouched; export creates a copy',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
              FilledButton(
                onPressed: _export,
                child: const Text('DONE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Canvas ----

  Widget _buildCanvas() {
    final bytes = _previewBytes;
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    Widget image = Image.memory(
      bytes,
      fit: BoxFit.contain,
      cacheWidth: 1600, // decode preview-sized; full-res only at export
    );

    if (_showAfter) {
      image = ColorFiltered(
        colorFilter: editPreviewFilter(_params),
        child: image,
      );

      if (_params.vignette > 0) {
        image = ShaderMask(
          shaderCallback: (rect) => RadialGradient(
            radius: 0.9,
            colors: [
              Colors.white,
              Colors.black.withValues(alpha: _params.vignette / 100.0 * 0.85),
            ],
            stops: const [0.55, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: image,
        );
      }

      if (_params.grain > 0) {
        image = IgnorePointer(
          child: CustomPaint(
            foregroundPainter: _GrainPainter(
              opacity: _params.grain / 100.0 * 0.3,
            ),
            child: image,
          ),
        );
      }
    }

    // Geometry preview (crop / rotate / keystone approximation)
    return Center(
      child: AspectRatio(
        aspectRatio: _previewAspectRatio(),
        child: AnimatedRotation(
          turns: _params.rotateQuarterTurns / 4,
          duration: const Duration(milliseconds: 250),
          child: Transform(
            transform: _keystonePreviewMatrix(),
            alignment: Alignment.center,
            child: image,
          ),
        ),
      ),
    );
  }

  double _previewAspectRatio() {
    final crop = _params.cropAspect;
    if (crop == null) return 3 / 4; // typical portrait sensor
    // Preview canvas keeps the crop frame; the image is cover-fitted inside
    return _params.rotateQuarterTurns.isOdd ? 1 / crop : crop;
  }

  Matrix4 _keystonePreviewMatrix() {
    if (_params.keystoneX == 0 && _params.keystoneY == 0) {
      return Matrix4.identity();
    }
    return Matrix4.identity()
      ..setEntry(3, 2, 0.0018)
      ..rotateX(_params.keystoneY / 100.0 * 0.55)
      ..rotateY(-_params.keystoneX / 100.0 * 0.55);
  }

  // ---- Tabs ----

  Widget _buildTabBar() {
    const tabs = ['LOOKS', 'ADJUST', 'CROP'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < tabs.length; i++)
          GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _tab == i ? Colors.tealAccent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  color: _tab == i ? Colors.white : Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControls() {
    switch (_tab) {
      case 0:
        return _buildLooksTab();
      case 1:
        return _buildAdjustTab();
      default:
        return _buildCropTab();
    }
  }

  Widget _buildLooksTab() {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: EffectPresets.list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final preset = EffectPresets.list[index];
          return GestureDetector(
            onTap: () => _update(_applyLook(preset)),
            child: Container(
              width: 88,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.tealAccent,
                  width: _looksSelected(preset) ? 2 : 0,
                ),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(6),
              child: Text(
                preset.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _looksSelected(preset) ? Colors.tealAccent : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _looksSelected(EffectPreset preset) {
    // A look is "selected" when its matrix matches the current parameters
    // closely (looks overwrite color params but keep geometry).
    if (_params.isIdentity && preset == EffectPresets.normal) return true;
    return false;
  }

  /// Looks are expressed as adjustment deltas so they compose with existing
  /// geometry edits and can be undone like any other change.
  EditParameters _applyLook(EffectPreset preset) {
    return switch (preset) {
      EffectPresets.normal => _params.copyWith(
          exposure: 0, brightness: 0, contrast: 0, saturation: 0,
          temperature: 0, tint: 0,
        ),
      EffectPresets.bw => _params.copyWith(saturation: -100, contrast: 12),
      EffectPresets.warm => _params.copyWith(temperature: 40),
      EffectPresets.cool => _params.copyWith(temperature: -40),
      EffectPresets.contrast => _params.copyWith(contrast: 32),
      EffectPresets.vintage => _params.copyWith(
          saturation: -28, temperature: 26, contrast: -8, shadows: 14),
      EffectPresets.cinema => _params.copyWith(
          temperature: -18, contrast: 16, saturation: -10, shadows: 10),
      EffectPresets.film => _params.copyWith(
          contrast: 14, saturation: -6, grain: 22, shadows: 8),
      EffectPresets.fade => _params.copyWith(
          contrast: -20, shadows: 22, highlights: -12),
      _ => _params,
    };
  }

  Widget _buildAdjustTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SliderRow(
            label: 'Exposure',
            value: _params.exposure,
            min: -2,
            max: 2,
            display: (v) => v.toStringAsFixed(2),
            onChanged: (v) =>
                _update(_params.copyWith(exposure: EditParameters.clampExposure(v))),
          ),
          _SliderRow(
            label: 'Brightness',
            value: _params.brightness,
            min: -100,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(brightness: EditParameters.clampAdjust(v))),
          ),
          _SliderRow(
            label: 'Contrast',
            value: _params.contrast,
            min: -100,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(contrast: EditParameters.clampAdjust(v))),
          ),
          _SliderRow(
            label: 'Highlights',
            value: _params.highlights,
            min: -100,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(highlights: EditParameters.clampAdjust(v))),
          ),
          _SliderRow(
            label: 'Shadows',
            value: _params.shadows,
            min: -100,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(shadows: EditParameters.clampAdjust(v))),
          ),
          _SliderRow(
            label: 'Saturation',
            value: _params.saturation,
            min: -100,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(saturation: EditParameters.clampAdjust(v))),
          ),
          _SliderRow(
            label: 'Temperature',
            value: _params.temperature,
            min: -100,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(temperature: EditParameters.clampAdjust(v))),
          ),
          _SliderRow(
            label: 'Tint',
            value: _params.tint,
            min: -100,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(tint: EditParameters.clampAdjust(v))),
          ),
          _SliderRow(
            label: 'Sharpness (on export)',
            value: _params.sharpness,
            min: 0,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(sharpness: EditParameters.clampPercent(v))),
          ),
          _SliderRow(
            label: 'Vignette',
            value: _params.vignette,
            min: 0,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(vignette: EditParameters.clampPercent(v))),
          ),
          _SliderRow(
            label: 'Grain',
            value: _params.grain,
            min: 0,
            max: 100,
            onChanged: (v) =>
                _update(_params.copyWith(grain: EditParameters.clampPercent(v))),
          ),
        ],
      ),
    );
  }

  Widget _buildCropTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Aspect presets
          Wrap(
            spacing: 8,
            children: [
              for (final aspect in const [
                (null, 'ORIGINAL'),
                (1.0, '1:1'),
                (4 / 3, '4:3'),
                (16 / 9, '16:9'),
                (3 / 2, '3:2'),
              ])
                GestureDetector(
                  onTap: () => _update(_params.copyWith(
                    cropAspect: aspect.$1,
                    clearCrop: aspect.$1 == null,
                  )),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _params.cropAspect == aspect.$1
                          ? Colors.tealAccent
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      aspect.$2,
                      style: TextStyle(
                        color: _params.cropAspect == aspect.$1
                            ? Colors.black
                            : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Rotate
          Row(
            children: [
              const Text(
                'ROTATE',
                style: TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _update(_params.copyWith(
                  rotateQuarterTurns: (_params.rotateQuarterTurns + 3) % 4,
                )),
                icon: const Icon(Icons.rotate_left, color: Colors.white),
                tooltip: 'Rotate left',
              ),
              IconButton(
                onPressed: () => _update(_params.copyWith(
                  rotateQuarterTurns: (_params.rotateQuarterTurns + 1) % 4,
                )),
                icon: const Icon(Icons.rotate_right, color: Colors.white),
                tooltip: 'Rotate right',
              ),
            ],
          ),
          // Keystone (perspective approximation)
          _SliderRow(
            label: 'Perspective H',
            value: _params.keystoneX,
            min: -30,
            max: 30,
            onChanged: (v) =>
                _update(_params.copyWith(keystoneX: v.clamp(-30.0, 30.0))),
          ),
          _SliderRow(
            label: 'Perspective V',
            value: _params.keystoneY,
            min: -30,
            max: 30,
            onChanged: (v) =>
                _update(_params.copyWith(keystoneY: v.clamp(-30.0, 30.0))),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double)? display;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.display,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.tealAccent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              display != null ? display!(value) : value.round().toString(),
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deterministic noise overlay approximating film grain in the preview.
class _GrainPainter extends CustomPainter {
  final double opacity;

  _GrainPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final random = math.Random(42); // fixed seed - stable across repaints
    final paint = Paint()..color = Colors.white.withValues(alpha: opacity);

    const dots = 1800;
    for (var i = 0; i < dots; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.7, paint);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.opacity != opacity;
}
