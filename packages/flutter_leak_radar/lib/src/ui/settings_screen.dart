// lib/src/ui/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/leak_radar_config.dart';
import '../leak_radar.dart';
import '../model/leak_kind.dart';
import 'theme/theme.dart';

/// Settings screen for configuring the LeakRadar detector at runtime.
///
/// All changes take effect immediately via [LeakRadar.updateConfig] and are
/// reflected across the app through [LeakRadar.configListenable].
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LeakRadarColors.pageBg,
      appBar: AppBar(
        backgroundColor: LeakRadarColors.appBarBg,
        elevation: 0,
        title: Text('Settings', style: LeakRadarText.title),
        iconTheme: const IconThemeData(color: LeakRadarColors.text100),
      ),
      body: ValueListenableBuilder<LeakRadarConfig>(
        valueListenable: LeakRadar.configListenable,
        builder: (context, config, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(label: 'OVERLAY'),
                const SizedBox(height: 8),
                _OverlaySection(config: config),
                const SizedBox(height: 24),
                _SectionHeader(label: 'REPORT THRESHOLD'),
                const SizedBox(height: 8),
                _ThresholdSection(config: config),
                const SizedBox(height: 24),
                _SectionHeader(label: 'AUTO-SCAN'),
                const SizedBox(height: 8),
                _AutoScanSection(config: config),
                const SizedBox(height: 24),
                _SectionHeader(label: 'PRECISION'),
                const SizedBox(height: 8),
                _PrecisionSection(config: config),
                const SizedBox(height: 32),
                _Footer(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: LeakRadarColors.text40,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Overlay section ───────────────────────────────────────────────────────────

class _OverlaySection extends StatelessWidget {
  const _OverlaySection({required this.config});

  final LeakRadarConfig config;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: _ToggleRow(
        toggleKey: const Key('settings_overlay_toggle'),
        label: 'Draggable badge',
        subtitle: 'Live worst-severity + count over your app',
        value: config.showOverlay,
        onChanged: (v) =>
            LeakRadar.updateConfig(config.copyWith(showOverlay: v)),
      ),
    );
  }
}

// ── Report threshold section ──────────────────────────────────────────────────

class _ThresholdSection extends StatelessWidget {
  const _ThresholdSection({required this.config});

  final LeakRadarConfig config;

  static const _segments = [
    LeakSeverity.info,
    LeakSeverity.warning,
    LeakSeverity.critical,
  ];

  static const _labels = ['Info', 'Warning', 'Critical'];

  static const _hints = [
    'Show all findings including informational',
    'Show warnings and critical only',
    'Show confirmed leaks only',
  ];

  @override
  Widget build(BuildContext context) {
    final selected = config.reportThreshold;
    final selectedIndex = _segments.indexOf(selected);
    final hint = selectedIndex >= 0 ? _hints[selectedIndex] : _hints[0];

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                for (var i = 0; i < _segments.length; i++) ...[
                  Expanded(
                    child: _SegmentButton(
                      label: _labels[i],
                      severity: _segments[i],
                      active: selected == _segments[i],
                      isFirst: i == 0,
                      isLast: i == _segments.length - 1,
                      onTap: () => LeakRadar.updateConfig(
                        config.copyWith(reportThreshold: _segments[i]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: LeakRadarColors.text40,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.severity,
    required this.active,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final String label;
  final LeakSeverity severity;
  final bool active;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  Color _severityColor(LeakSeverity s) => switch (s) {
    LeakSeverity.critical => LeakRadarColors.severityCritical,
    LeakSeverity.warning => LeakRadarColors.severityWarning,
    LeakSeverity.info => LeakRadarColors.severityInfo,
  };

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(severity);
    final radius = BorderRadius.horizontal(
      left: isFirst ? const Radius.circular(8) : Radius.zero,
      right: isLast ? const Radius.circular(8) : Radius.zero,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          border: Border.all(color: active ? color : LeakRadarColors.border08),
          borderRadius: radius,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: active ? LeakRadarColors.pageBg : LeakRadarColors.text40,
          ),
        ),
      ),
    );
  }
}

// ── Auto-scan section ─────────────────────────────────────────────────────────

class _AutoScanSection extends StatelessWidget {
  const _AutoScanSection({required this.config});

  final LeakRadarConfig config;

  static const _manual = AutoScan();
  static const _periodic = AutoScan(period: Duration(seconds: 30));
  static const _onNav = AutoScan(onNavigation: true);

  AutoScan get _selected {
    final a = config.autoScan;
    if (a.onNavigation) return _onNav;
    if (a.hasPeriodic) return _periodic;
    return _manual;
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return _SettingsCard(
      child: Column(
        children: [
          _RadioRow(
            label: 'Manual only',
            subtitle: 'Tap Scan now to capture',
            value: _manual,
            groupValue: sel,
            onChanged: (v) =>
                LeakRadar.updateConfig(config.copyWith(autoScan: v)),
          ),
          const _Divider(),
          _RadioRow(
            label: 'Periodic · 30 s',
            subtitle: 'Scans every 30 seconds automatically',
            value: _periodic,
            groupValue: sel,
            onChanged: (v) =>
                LeakRadar.updateConfig(config.copyWith(autoScan: v)),
          ),
          const _Divider(),
          _RadioRow(
            label: 'On screen-pop',
            subtitle: 'Scans after each navigation back',
            value: _onNav,
            groupValue: sel,
            recommended: true,
            onChanged: (v) =>
                LeakRadar.updateConfig(config.copyWith(autoScan: v)),
          ),
        ],
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.recommended = false,
  });

  final String label;
  final String subtitle;
  final AutoScan value;
  final AutoScan groupValue;
  final ValueChanged<AutoScan> onChanged;
  final bool recommended;

  bool get _selected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        decoration: BoxDecoration(
          border: _selected
              ? Border.all(color: LeakRadarColors.accent.withValues(alpha: 0.4))
              : null,
          borderRadius: BorderRadius.circular(8),
          color: _selected
              ? LeakRadarColors.accent.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: LeakRadarColors.text100,
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 8),
                        _RecommendedTag(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: LeakRadarColors.text40,
                    ),
                  ),
                ],
              ),
            ),
            _RadioDot(selected: _selected),
          ],
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? LeakRadarColors.accent : LeakRadarColors.text40,
          width: selected ? 2 : 1.5,
        ),
        color: Colors.transparent,
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: LeakRadarColors.accent,
                ),
              ),
            )
          : null,
    );
  }
}

class _RecommendedTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: LeakRadarColors.accent.withValues(alpha: 0.15),
        border: Border.all(
          color: LeakRadarColors.accent.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'RECOMMENDED',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: LeakRadarColors.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Precision section ─────────────────────────────────────────────────────────

class _PrecisionSection extends StatelessWidget {
  const _PrecisionSection({required this.config});

  final LeakRadarConfig config;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: _ToggleRow(
        toggleKey: const Key('settings_precision_toggle'),
        label: 'Precise opt-in tracking',
        subtitle: 'Honor track() / markDisposed()',
        value: config.preciseTracking,
        onChanged: (v) =>
            LeakRadar.updateConfig(config.copyWith(preciseTracking: v)),
      ),
    );
  }
}

// ── Shared toggle row ─────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    this.toggleKey,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key? toggleKey;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: LeakRadarColors.text100,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: LeakRadarColors.text40,
                ),
              ),
            ],
          ),
        ),
        _Toggle(key: toggleKey, value: value, onChanged: onChanged),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 26,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? LeakRadarColors.accent : const Color(0x24FFFFFF),
        ),
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared card ───────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LeakRadarTheme.cardPadding),
      decoration: BoxDecoration(
        color: LeakRadarColors.cardBg,
        border: Border.all(color: LeakRadarColors.border08),
        borderRadius: BorderRadius.circular(LeakRadarTheme.cardRadius),
      ),
      child: child,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Divider(color: LeakRadarColors.border08, height: 1, thickness: 1),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Debug & profile only · no-op in release\n'
      'Never throws · never measurably slows the host',
      textAlign: TextAlign.center,
      style: LeakRadarText.mono.copyWith(
        color: LeakRadarColors.text25,
        fontSize: 11,
      ),
    );
  }
}
