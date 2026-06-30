// lib/src/ui/perf_radar_view.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:radar_ui/radar_ui.dart';

export 'widgets/stability_panel.dart';

import '../facade/perf_radar.dart';
import '../model/frame_stats.dart';
import '../model/stability_snapshot.dart';
import 'widgets/frames_tab.dart';
import 'widgets/rebuilds_tab.dart';
import 'widgets/startup_tab.dart';
import 'widgets/traces_tab.dart';

// ── Sub-tab index ─────────────────────────────────────────────────────────────

enum _PerfSubTab { traces, frames, rebuilds, startup }

// ── Public embed widget ───────────────────────────────────────────────────────

/// Tabbed body view of the Perf Radar inspector.
///
/// Renders four performance sub-tabs — Traces · Frames · Rebuilds · Startup —
/// and keeps the Stability panel accessible for the umbrella [RadarScreen].
///
/// No [Scaffold] or [AppBar] — designed to be embedded in a containing
/// [Scaffold], for example in [PerfRadarScreen] or in a combined radar screen.
///
/// Refreshes data from [PerfRadar] every two seconds.
class PerfRadarView extends StatefulWidget {
  /// Creates a [PerfRadarView].
  const PerfRadarView({super.key});

  @override
  State<PerfRadarView> createState() => _PerfRadarViewState();
}

class _PerfRadarViewState extends State<PerfRadarView> {
  late FrameStatsSnapshot _frameStats;
  late StabilitySnapshot _stability;
  late TraceSnapshot _snapshot;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    setState(() {
      _snapshot = PerfRadar.snapshot();
      _frameStats = PerfRadar.frameStats;
      _stability = PerfRadar.stabilitySnapshot;
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PerfTabs(
      snapshot: _snapshot,
      frameStats: _frameStats,
      stability: _stability,
    );
  }
}

// ── Tabbed shell ──────────────────────────────────────────────────────────────

class _PerfTabs extends StatefulWidget {
  const _PerfTabs({
    required this.snapshot,
    required this.frameStats,
    required this.stability,
  });

  final TraceSnapshot snapshot;
  final FrameStatsSnapshot frameStats;
  final StabilitySnapshot stability;

  @override
  State<_PerfTabs> createState() => _PerfTabsState();
}

class _PerfTabsState extends State<_PerfTabs> {
  _PerfSubTab _activeTab = _PerfSubTab.traces;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubTabBar(
          active: _activeTab,
          onSelect: (t) => setState(() => _activeTab = t),
        ),
        const Divider(height: 1, thickness: 1, color: RadarColors.hairline08),
        Expanded(child: _tabBody()),
      ],
    );
  }

  Widget _tabBody() {
    return switch (_activeTab) {
      _PerfSubTab.traces => TracesTab(snapshot: widget.snapshot),
      _PerfSubTab.frames => FramesTab(stats: widget.frameStats),
      _PerfSubTab.rebuilds => RebuildsTab(snapshot: widget.snapshot),
      _PerfSubTab.startup => StartupTab(snapshot: widget.snapshot),
    };
  }
}

// ── Sub-tab bar ───────────────────────────────────────────────────────────────

class _SubTabBar extends StatelessWidget {
  const _SubTabBar({required this.active, required this.onSelect});

  final _PerfSubTab active;
  final ValueChanged<_PerfSubTab> onSelect;

  static const _labels = {
    _PerfSubTab.traces: 'Traces',
    _PerfSubTab.frames: 'Frames',
    _PerfSubTab.rebuilds: 'Rebuilds',
    _PerfSubTab.startup: 'Startup',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RadarColors.bgPanel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _PerfSubTab.values.map((tab) {
            final isActive = tab == active;
            return _SubTabChip(
              label: _labels[tab]!,
              isActive: isActive,
              onTap: () => onSelect(tab),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SubTabChip extends StatelessWidget {
  const _SubTabChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF151c20) : Colors.transparent,
          borderRadius: RadarDensity.chipRadius,
          border: Border.all(
            color: isActive ? RadarColors.hairline12 : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: RadarTypography.monoLabel.copyWith(
            color: isActive ? RadarColors.text100 : RadarColors.text40,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
