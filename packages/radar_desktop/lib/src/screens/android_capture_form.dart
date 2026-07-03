import 'package:flutter/material.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';

/// Duration presets offered for an on-device capture, in milliseconds.
/// Extracted alongside the row widgets below (`android_capture_screen.dart`
/// stays under the repo's file-size guidance) — mirrors the
/// `android_native_module_row.dart` extraction precedent.
const List<int> captureDurationPresetsMs = [15000, 30000, 60000];

/// Shown in place of the capture form when
/// `NativeProfilingController.canCapture` is false, i.e. this build/host has
/// no `adb` capture seams wired up.
class NoCaptureDeviceHint extends StatelessWidget {
  const NoCaptureDeviceHint({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.phone_android,
              size: 16,
              color: RadarColors.text40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Connect a device & enable USB debugging to run a device '
                'capture.',
                style: RadarTypography.monoLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The enabled device-capture form: device picker, package, mode, duration,
/// and the capture action itself. Purely presentational — all state and
/// wiring live in `android_capture_screen.dart`'s state class.
class AndroidCaptureForm extends StatelessWidget {
  const AndroidCaptureForm({
    super.key,
    required this.devices,
    required this.selectedSerial,
    required this.probing,
    required this.capturing,
    required this.mode,
    required this.durationMs,
    required this.justCaptured,
    required this.onSelectDevice,
    required this.onRefreshDevices,
    required this.onPackageChanged,
    required this.onModeChanged,
    required this.onDurationChanged,
    required this.onCapture,
  });

  final List<AndroidDevice> devices;
  final String? selectedSerial;
  final bool probing;
  final bool capturing;
  final CaptureMode mode;
  final int durationMs;
  final bool justCaptured;
  final ValueChanged<String> onSelectDevice;
  final VoidCallback? onRefreshDevices;
  final ValueChanged<String> onPackageChanged;
  final ValueChanged<CaptureMode> onModeChanged;
  final ValueChanged<int> onDurationChanged;
  final VoidCallback? onCapture;

  bool get _busy => probing || capturing;

  String get _deviceLabel {
    for (final device in devices) {
      if (device.serial == selectedSerial) return device.label;
    }
    return selectedSerial ?? 'device';
  }

  @override
  Widget build(BuildContext context) {
    final ready = devices.where((d) => d.isReady).toList();
    final unready = devices.where((d) => !d.isReady).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_android, size: 16),
                const SizedBox(width: 8),
                Text('Run device capture', style: RadarTypography.monoBody),
                const Spacer(),
                if (probing) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh devices',
                  onPressed: onRefreshDevices,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ..._deviceSection(ready, unready),
            const SizedBox(height: 12),
            TextField(
              enabled: !_busy,
              onChanged: onPackageChanged,
              style: RadarTypography.monoInput,
              decoration: const InputDecoration(
                labelText: 'Package',
                hintText: 'com.katim.leak_lab',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            CaptureModeToggle(
              mode: mode,
              enabled: !_busy,
              onChanged: onModeChanged,
            ),
            const SizedBox(height: 12),
            CaptureDurationChips(
              durationMs: durationMs,
              enabled: !_busy,
              onChanged: onDurationChanged,
            ),
            const SizedBox(height: 14),
            if (capturing) ...[
              const RadarLinearProgress(),
              const SizedBox(height: 8),
              Text(
                'Capturing from $_deviceLabel… (${durationMs ~/ 1000}s)',
                style: RadarTypography.caption,
              ),
              const SizedBox(height: 10),
            ],
            if (onCapture == null &&
                !capturing &&
                ready.isEmpty &&
                devices.isNotEmpty) ...[
              Text(
                'Connect an authorized device to capture',
                style: RadarTypography.caption,
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: onCapture,
              icon: const Icon(Icons.fiber_manual_record, size: 14),
              label: const Text('Capture'),
            ),
            if (justCaptured && !capturing) ...[
              const SizedBox(height: 8),
              Text(
                'Captured & imported',
                style: RadarTypography.caption.copyWith(
                  color: RadarColors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The device row: an always-visible caption when [devices] is empty or
  /// no device is ready, else the ready-only dropdown plus a caption
  /// noting any not-ready devices left out of it.
  List<Widget> _deviceSection(
    List<AndroidDevice> ready,
    List<AndroidDevice> unready,
  ) {
    if (devices.isEmpty) {
      return [
        Text(
          'No device detected — connect one & enable USB debugging',
          style: RadarTypography.caption,
        ),
      ];
    }

    if (ready.isEmpty) {
      final anyUnauthorized = unready.any((d) => d.state == 'unauthorized');
      return [
        Text(
          anyUnauthorized
              ? 'Device unauthorized — accept the USB-debugging prompt on '
                    'the device, then refresh'
              : 'Device offline — reconnect it, then refresh',
          style: RadarTypography.caption,
        ),
      ];
    }

    return [
      DropdownButton<String>(
        value: selectedSerial,
        isExpanded: true,
        dropdownColor: RadarColors.bgSurface,
        style: RadarTypography.monoBody,
        items: [
          for (final device in ready)
            DropdownMenuItem(value: device.serial, child: Text(device.label)),
        ],
        onChanged: _busy
            ? null
            : (serial) {
                if (serial != null) onSelectDevice(serial);
              },
      ),
      if (unready.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          '${unready.length} other device(s) not ready '
          '(unauthorized/offline)',
          style: RadarTypography.caption,
        ),
      ],
    ];
  }
}

/// Attach-vs-startup toggle, built from [RadarFilterChip] to match the
/// app's existing filter-chip strips rather than a stock Material control.
class CaptureModeToggle extends StatelessWidget {
  const CaptureModeToggle({
    super.key,
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final CaptureMode mode;
  final bool enabled;
  final ValueChanged<CaptureMode> onChanged;

  static String _labelFor(CaptureMode mode) => switch (mode) {
    CaptureMode.attach => 'Attach (running app)',
    CaptureMode.startup => 'Startup (from launch)',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in CaptureMode.values)
          RadarFilterChip(
            label: _labelFor(option),
            selected: option == mode,
            onSelected: enabled ? () => onChanged(option) : () {},
          ),
      ],
    );
  }
}

/// Duration-preset chips (15s / 30s / 60s), also built from
/// [RadarFilterChip].
class CaptureDurationChips extends StatelessWidget {
  const CaptureDurationChips({
    super.key,
    required this.durationMs,
    required this.enabled,
    required this.onChanged,
  });

  final int durationMs;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final ms in captureDurationPresetsMs)
          RadarFilterChip(
            label: '${ms ~/ 1000}s',
            selected: ms == durationMs,
            onSelected: enabled ? () => onChanged(ms) : () {},
          ),
      ],
    );
  }
}
