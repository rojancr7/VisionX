import 'package:flutter/material.dart';
import '../providers/camera_provider.dart';

/// Lens selector chips backed by the device's REAL physical cameras.
///
/// Only shown when the device reports multiple back lenses (ultrawide /
/// main / telephoto). Selecting a chip performs an actual camera switch -
/// no fake focal-length changes.
class LensSelector extends StatelessWidget {
  final CameraProvider cameraProvider;

  const LensSelector({super.key, required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    if (cameraProvider.isFrontCamera) return const SizedBox.shrink();
    if (cameraProvider.backLenses.length < 2) return const SizedBox.shrink();

    final bases = cameraProvider.lensBaseFactors;
    final current = cameraProvider.lensIndex;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cameraProvider.backLenses.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _LensChip(
            label: _formatBase(bases.length > i ? bases[i] : 1.0),
            selected: i == current,
            onTap: () => cameraProvider.selectLens(i),
          ),
        ],
      ],
    );
  }

  String _formatBase(double v) =>
      v == v.roundToDouble() ? '${v.round()}x' : '${v.toStringAsFixed(1)}x';
}

class _LensChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LensChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.black.withValues(alpha: 0.75)
              : Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.tealAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.tealAccent : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
