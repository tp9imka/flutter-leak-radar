import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../app/desktop_view.dart';

/// The 210px left navigation. MEMORY and ANDROID NATIVE groups are always
/// active (both are offline workspaces); PERFORMANCE and STABILITY are
/// locked (dimmed, non-interactive) until [connected].
class DesktopRail extends StatelessWidget {
  const DesktopRail({
    super.key,
    required this.current,
    required this.onSelect,
    required this.connected,
  });

  final DesktopView current;
  final ValueChanged<DesktopView> onSelect;
  final bool connected;

  static const double width = 210;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: RadarColors.bgRail,
      padding: const EdgeInsets.symmetric(vertical: 12),
      // Scrollable: the rail now holds four groups (MEMORY, PERFORMANCE,
      // STABILITY, ANDROID NATIVE) and no longer reliably fits a short
      // window/test surface without overflowing.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _group('MEMORY'),
            for (final v in const [
              DesktopView.dumps,
              DesktopView.histogram,
              DesktopView.paths,
              DesktopView.clusters,
              DesktopView.compare,
              DesktopView.trends,
            ])
              _item(v, enabled: true),
            const SizedBox(height: 14),
            _group('PERFORMANCE', locked: !connected),
            for (final v in const [DesktopView.traces, DesktopView.frames])
              _item(v, enabled: connected),
            const SizedBox(height: 14),
            _group('STABILITY', locked: !connected),
            for (final v in const [DesktopView.errors, DesktopView.stalls])
              _item(v, enabled: connected),
            const SizedBox(height: 14),
            _group('ANDROID NATIVE'),
            for (final v in const [
              DesktopView.androidSession,
              DesktopView.androidNative,
              DesktopView.androidCompare,
              DesktopView.androidFfi,
              DesktopView.androidCapture,
            ])
              _item(v, enabled: true),
            const SizedBox(height: 14),
            // Import-first, so always active even offline; its live tab gates
            // itself on the connection internally.
            _group('DEVICE'),
            _item(DesktopView.deviceMonitor, enabled: true),
            const SizedBox(height: 14),
            _group('SETUP'),
            // Always enabled, even offline: the Tools screen is how a
            // user fixes a missing external tool in the first place, so
            // it can never be behind the same connection gate it helps
            // unblock.
            _item(DesktopView.tools, enabled: true),
          ],
        ),
      ),
    );
  }

  Widget _group(String title, {bool locked = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
    child: Row(
      children: [
        Text(
          title,
          style: RadarTypography.monoLabel.copyWith(
            color: RadarColors.text25,
            letterSpacing: 1,
          ),
        ),
        if (locked) ...[
          const SizedBox(width: 6),
          Icon(Icons.lock_outline, size: 11, color: RadarColors.text15),
        ],
      ],
    ),
  );

  Widget _item(DesktopView v, {required bool enabled}) {
    final active = v == current;
    final color = !enabled
        ? RadarColors.text15
        : active
        ? RadarColors.accent
        : RadarColors.text60;
    return InkWell(
      onTap: enabled ? () => onSelect(v) : null,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: active ? RadarColors.accentSubtle : null,
        alignment: Alignment.centerLeft,
        child: Text(
          v.label,
          style: RadarTypography.monoBody.copyWith(color: color),
        ),
      ),
    );
  }
}
