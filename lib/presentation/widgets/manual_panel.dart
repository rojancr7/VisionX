import 'package:flutter/material.dart';
import '../providers/camera_provider.dart';

/// Expandable manual control panel (Phase 5).
///
/// Only controls the underlying camera API actually supports are enabled.
/// The `camera` plugin does not expose manual ISO, shutter speed or white
/// balance, so those rows are shown disabled with a clear explanation
/// instead of being silently broken.
class ManualPanel extends StatelessWidget {
  final CameraProvider cameraProvider;

  const ManualPanel({super.key, required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    final features = cameraProvider.features;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manual controls',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // EXPOSURE compensation (supported)
            _SectionLabel('EXPOSURE'),
            const SizedBox(height: 8),
            features.exposureOffset
                ? _ExposureRow(cameraProvider: cameraProvider)
                : const _UnsupportedNote(
                    'Exposure compensation is not supported on this camera'),
            const SizedBox(height: 16),

            // FOCUS (tap-to-focus + lock supported via focus point API)
            _SectionLabel('FOCUS'),
            const SizedBox(height: 8),
            features.focusPoint
                ? _FocusRow(cameraProvider: cameraProvider)
                : const _UnsupportedNote(
                    'Manual focus selection is not supported on this camera'),
            const SizedBox(height: 16),

            // ISO - not exposed by the camera plugin
            _SectionLabel('ISO'),
            const _ValueChips(
              values: ['AUTO', '100', '200', '400', '800', '1600'],
              enabled: false,
            ),
            const _UnsupportedNote(
                'Manual ISO is not exposed by the camera API on this device'),
            const SizedBox(height: 16),

            // Shutter speed - not exposed by the camera plugin
            _SectionLabel('SHUTTER'),
            const _ValueChips(
              values: ['AUTO', '1/30', '1/60', '1/125', '1/250'],
              enabled: false,
            ),
            const _UnsupportedNote(
                'Manual shutter speed is not exposed by the camera API'),
            const SizedBox(height: 16),

            // White balance - not exposed by the camera plugin
            _SectionLabel('WHITE BALANCE'),
            const _ValueChips(
              values: ['AUTO', '3200K', '4500K', '5600K', '6500K'],
              enabled: false,
            ),
            const _UnsupportedNote(
                'Manual white balance is not exposed by the camera API'),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.tealAccent.withValues(alpha: 0.9),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _UnsupportedNote extends StatelessWidget {
  final String text;

  const _UnsupportedNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white24, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExposureRow extends StatefulWidget {
  final CameraProvider cameraProvider;

  const _ExposureRow({required this.cameraProvider});

  @override
  State<_ExposureRow> createState() => _ExposureRowState();
}

class _ExposureRowState extends State<_ExposureRow> {
  @override
  Widget build(BuildContext context) {
    final provider = widget.cameraProvider;
    final min = provider.minExposureOffset;
    final max = provider.maxExposureOffset;
    final step = provider.exposureStep > 0 ? provider.exposureStep : 0.1;
    final value = provider.exposureOffset.clamp(min, max).toDouble();
    final divisions = ((max - min) / step).round().clamp(1, 200);

    return Row(
      children: [
        SizedBox(
          width: 220,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              activeTrackColor: Colors.tealAccent,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: provider.evLabel,
              onChanged: (v) => provider.setExposureOffsetEv(v),
            ),
          ),
        ),
        IconButton(
          onPressed: provider.exposureOffset == 0
              ? null
              : () => provider.resetExposureOffset(),
          icon: const Icon(Icons.restart_alt, color: Colors.white70, size: 20),
          tooltip: 'Reset to 0 EV',
        ),
      ],
    );
  }
}

class _FocusRow extends StatelessWidget {
  final CameraProvider cameraProvider;

  const _FocusRow({required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _FocusChip(
              label: 'AUTO',
              selected: !cameraProvider.focusLocked,
              onTap: cameraProvider.focusLocked
                  ? () => cameraProvider.toggleFocusLock()
                  : null,
            ),
            const SizedBox(width: 8),
            _FocusChip(
              label: 'LOCKED',
              selected: cameraProvider.focusLocked,
              onTap: cameraProvider.focusLocked
                  ? null
                  : () => cameraProvider.toggleFocusLock(),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Tap the preview to focus and meter. Hold to lock AF.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _FocusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _FocusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.white12,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ValueChips extends StatelessWidget {
  final List<String> values;
  final bool enabled;

  const _ValueChips({required this.values, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.3,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: v == 'AUTO' ? Colors.white24 : Colors.white12,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                v,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
