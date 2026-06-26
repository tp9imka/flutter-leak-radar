import 'dart:async';

import 'package:flutter/material.dart';
import 'package:radar_trace/radar_trace.dart';

import '../facade/perf_radar.dart';
import '../model/frame_stats.dart';
import '../model/stability_snapshot.dart';
import 'widgets/frame_stats_panel.dart';
import 'widgets/rebuild_counts_panel.dart';
import 'widgets/span_stats_table.dart';
import 'widgets/stability_panel.dart';

/// Tabbed body view of the Perf Radar inspector (Spans / Frames / Stability).
///
/// Owns a [DefaultTabController] with 3 tabs, a [TabBar], and a
/// [TabBarView]. No [Scaffold] or [AppBar] — designed to be embedded in a
/// containing [Scaffold], for example in [PerfRadarScreen] or in a combined
/// radar screen.
///
/// Refreshes data from [PerfRadar] every 2 seconds.
class PerfRadarView extends StatefulWidget {
  /// Creates a [PerfRadarView].
  const PerfRadarView({super.key});

  @override
  State<PerfRadarView> createState() => _PerfRadarViewState();
}

class _PerfRadarViewState extends State<PerfRadarView> {
  late FrameStatsSnapshot _frameStats;
  late StabilitySnapshot _stability;
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
      _frameStats = PerfRadar.frameStats;
      _stability = PerfRadar.stabilitySnapshot;
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  TraceSnapshot get _snapshot => PerfRadar.snapshot();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: Color(0xFF2fe39b),
            unselectedLabelColor: Color(0xFF7d8e94),
            indicatorColor: Color(0xFF2fe39b),
            tabs: [
              Tab(text: 'Spans'),
              Tab(text: 'Frames'),
              Tab(text: 'Stability'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SpansTab(snapshot: _snapshot),
                FrameStatsPanel(stats: _frameStats),
                StabilityPanel(stability: _stability),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpansTab extends StatelessWidget {
  const _SpansTab({required this.snapshot});

  final TraceSnapshot snapshot;

  bool _hasRebuildSpans() =>
      snapshot.stats.keys.any((k) => k.name.startsWith('rebuild:'));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_hasRebuildSpans()) ...[
          RebuildCountsPanel(snapshot: snapshot),
          const Divider(height: 1, thickness: 1, color: Color(0xFF1e2a2f)),
        ],
        Expanded(child: SpanStatsTable(snapshot: snapshot)),
      ],
    );
  }
}
