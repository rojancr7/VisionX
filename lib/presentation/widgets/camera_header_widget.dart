import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../providers/camera_provider.dart';
import 'manual_panel.dart';

/// Top control bar: flash, HDR (disabled when unsupported), self-timer,
/// grid, level, monitoring, manual controls and effects toggles.
class CameraHeaderWidget extends StatelessWidget {
  final CameraProvider cameraProvider;

  const CameraHeaderWidget({
    super.key,
    required this.cameraProvider,
  });

  @override
  Widget build(BuildContext context) {
    final locked =
        cameraProvider.isRecording || cameraProvider.isCountingDown;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.65),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Flash
              if (!cameraProvider.isFrontCamera)
                _Chip(
                  icon: _flashIcon(cameraProvider.settings.flashMode),
                  active: cameraProvider.settings.flashMode != FlashMode.off,
                  enabled: !locked,
                  onTap: cameraProvider.cycleFlashMode,
                )
              else
                const SizedBox(width: 40),

              const SizedBox(width: 4),

              // HDR - the camera plugin does not expose an HDR API, so this
              // is always disabled with a clear explanation.
              _Chip(
                icon: Icons.hdr_on,
                active: false,
                enabled: false,
                tooltip: 'HDR is not supported by the camera API on this device',
                onTap: null,
              ),

              const SizedBox(width: 4),

              // Self-timer chip (cycles Off -> 3s -> 10s)
              _Chip(
                icon: Icons.timer_outlined,
                label: cameraProvider.settings.timerSeconds != null
                    ? '${cameraProvider.settings.timerSeconds}s'
                    : null,
                active: cameraProvider.settings.timerSeconds != null,
                enabled: !locked,
                onTap: _cycleTimer,
              ),

              const Spacer(),

              // Grid
              _Chip(
                icon: Icons.grid_3x3_outlined,
                active: cameraProvider.settings.gridEnabled,
                enabled: !locked,
                onTap: cameraProvider.toggleGrid,
              ),

              const SizedBox(width: 4),

              // Level
              _Chip(
                icon: Icons.explore_outlined,
                active: cameraProvider.settings.levelEnabled,
                enabled: !locked,
                onTap: cameraProvider.toggleLevel,
              ),

              const SizedBox(width: 4),

              // Monitoring tools (histogram, zebra, ...)
              _Chip(
                icon: Icons.monitor_heart_outlined,
                active: cameraProvider.isMonitoringActive,
                enabled: !locked,
                onTap: () => _showMonitoringSheet(context),
              ),

              const SizedBox(width: 4),

              // Manual controls
              _Chip(
                icon: Icons.tune,
                active: cameraProvider.manualPanelOpen,
                enabled: !locked,
                onTap: () => _showManualSheet(context),
              ),

              const SizedBox(width: 4),

              // Effects
              _Chip(
                icon: Icons.auto_awesome_outlined,
                active: cameraProvider.settings.effectIndex != 0 ||
                    cameraProvider.effectsPanelOpen,
                enabled: !locked,
                onTap: () => cameraProvider
                    .setEffectsPanelOpen(!cameraProvider.effectsPanelOpen),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleTimer() {
    final current = cameraProvider.settings.timerSeconds;
    if (current == null) {
      cameraProvider.setTimer(3);
    } else if (current == 3) {
      cameraProvider.setTimer(10);
    } else {
      cameraProvider.setTimer(null);
    }
  }

  void _showMonitoringSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MonitoringSheet(cameraProvider: cameraProvider),
    );
  }

  void _showManualSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ManualPanel(cameraProvider: cameraProvider),
    );
  }

  IconData _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }
}

/// Compact circular control chip
class _Chip extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool active;
  final bool enabled;
  final String? tooltip;
  final VoidCallback? onTap;

  const _Chip({
    required this.icon,
    this.label,
    required this.active,
    required this.enabled,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.85)
                : Colors.black.withValues(alpha: 0.45),
          ),
          child: Center(
            child: label != null
                ? Text(
                    label!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : Icon(
                    icon,
                    color: active ? Colors.black : Colors.white,
                    size: 20,
                  ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/// Monitoring tools bottom sheet
class MonitoringSheet extends StatelessWidget {
  final CameraProvider cameraProvider;

  const MonitoringSheet({super.key, required this.cameraProvider});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monitoring',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _SheetToggle(
              icon: Icons.grid_3x3_outlined,
              title: 'Grid',
              value: cameraProvider.settings.gridEnabled,
              onChanged: (_) => cameraProvider.toggleGrid(),
            ),
            _SheetToggle(
              icon: Icons.explore_outlined,
              title: 'Level',
              value: cameraProvider.settings.levelEnabled,
              onChanged: (_) => cameraProvider.toggleLevel(),
            ),
            _SheetToggle(
              icon: Icons.equalizer,
              title: 'Histogram',
              value: cameraProvider.settings.histogramEnabled,
              onChanged: (_) => cameraProvider.toggleHistogram(),
            ),
            _SheetToggle(
              icon: Icons.waterfall_chart,
              title: 'Zebra',
              value: cameraProvider.settings.zebraEnabled,
              onChanged: (_) => cameraProvider.toggleZebra(),
            ),
            _SheetToggle(
              icon: Icons.warning_amber_outlined,
              title: 'Highlight warning',
              value: cameraProvider.settings.highlightWarningEnabled,
              onChanged: (_) => cameraProvider.toggleHighlightWarning(),
            ),
            _SheetToggle(
              icon: Icons.speed_outlined,
              title: 'Exposure meter',
              value: cameraProvider.settings.exposureMeterEnabled,
              onChanged: (_) => cameraProvider.toggleExposureMeter(),
            ),
            _UnsupportedRow(
              title: 'Focus peaking',
              reason: 'Per-frame edge analysis is not supported by the '
                  'camera plugin on this device',
            ),
            _UnsupportedRow(
              title: 'HDR',
              reason: 'Not exposed by the camera API on this device',
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SheetToggle({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _UnsupportedRow extends StatelessWidget {
  final String title;
  final String reason;

  const _UnsupportedRow({required this.title, required this.reason});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: false,
      leading: const Icon(Icons.block, color: Colors.white24, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white24)),
      subtitle: Text(
        reason,
        style: const TextStyle(color: Colors.white24, fontSize: 11),
      ),
    );
  }
}
