import 'package:flutter/material.dart';
import '../../domain/models/effect_preset.dart';
import '../providers/camera_provider.dart';

/// Horizontal scrollable real-time effect selector.
///
/// The camera plugin renders the preview natively, so effects cannot be
/// applied to the LIVE preview; the selected look is applied non-destructively
/// when the photo is captured (the untouched original is always kept).
class EffectsPanel extends StatelessWidget {
  final CameraProvider cameraProvider;

  const EffectsPanel({super.key, required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  const Text(
                    'EFFECTS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => cameraProvider.setEffectsPanelOpen(false),
                    child: const Icon(Icons.close, color: Colors.white70,
                        size: 20),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: EffectPresets.list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final preset = EffectPresets.list[index];
                  final selected = cameraProvider.settings.effectIndex == index;
                  return GestureDetector(
                    onTap: () => cameraProvider.setEffect(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        preset.name,
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 16, right: 16, bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Applied when you take the photo - the original is always kept untouched',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
