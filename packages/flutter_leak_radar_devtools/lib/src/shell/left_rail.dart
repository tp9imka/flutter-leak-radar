import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../memory/memory_view.dart';

/// Fixed-width left navigation rail for the Leak Radar DevTools extension.
///
/// Width is 198px. Shows three active Memory destinations, two disabled
/// Performance placeholders, and two disabled Stability placeholders.
/// A footer note clarifies the runtime environment restriction.
class LeftRail extends StatelessWidget {
  const LeftRail({
    super.key,
    required this.currentView,
    required this.onViewChanged,
  });

  final MemoryView currentView;
  final ValueChanged<MemoryView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RadarColors.bgRail,
        border: Border(
          right: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: SizedBox(
        width: 198,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            _SectionLabel('MEMORY'),
            _NavItem(
              label: 'Snapshot & diff',
              view: MemoryView.snapshotDiff,
              currentView: currentView,
              onTap: onViewChanged,
            ),
            _NavItem(
              label: 'Class histogram',
              view: MemoryView.classHistogram,
              currentView: currentView,
              onTap: onViewChanged,
            ),
            _NavItem(
              label: 'Retaining paths',
              view: MemoryView.retainingPaths,
              currentView: currentView,
              onTap: onViewChanged,
            ),
            const SizedBox(height: 8),
            _SectionLabel('PERFORMANCE'),
            _DisabledNavItem(label: 'Traces'),
            _DisabledNavItem(label: 'Frames'),
            const SizedBox(height: 8),
            _SectionLabel('STABILITY'),
            _DisabledNavItem(label: 'Errors'),
            _DisabledNavItem(label: 'Stalls'),
            const Spacer(),
            const _RailFooter(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        text,
        style: RadarTypography.monoLabel.copyWith(
          color: RadarColors.text25,
          letterSpacing: 0.08 * 10.5,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.view,
    required this.currentView,
    required this.onTap,
  });

  final String label;
  final MemoryView view;
  final MemoryView currentView;
  final ValueChanged<MemoryView> onTap;

  bool get _isActive => view == currentView;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(view),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _isActive ? RadarColors.accentSubtle : Colors.transparent,
        ),
        child: SizedBox(
          height: 34,
          child: Row(
            children: [
              // Left accent bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 3,
                color: _isActive ? RadarColors.accent : Colors.transparent,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: RadarTypography.monoBody.copyWith(
                    fontSize: 12.5,
                    color: _isActive ? RadarColors.accent : RadarColors.text60,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisabledNavItem extends StatelessWidget {
  const _DisabledNavItem({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Available in the in-app Inspector — host-side wiring pending',
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: RadarTypography.monoBody.copyWith(
                  fontSize: 12.5,
                  color: RadarColors.text25,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _RailFooter extends StatelessWidget {
  const _RailFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        'debug / profile only · no-op in release',
        style: RadarTypography.caption.copyWith(
          color: RadarColors.text25,
          fontSize: 10,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
