import 'dart:async';

import 'package:flutter/material.dart';

import '../facade/perf_radar.dart';
import '../model/frame_stats.dart';
import '../model/stability_snapshot.dart';
import 'widgets/frame_stats_panel.dart';
import 'widgets/span_stats_table.dart';
import 'widgets/stability_panel.dart';

/// Full-screen inspector with three tabs: Spans, Frames, Stability.
///
/// Refreshes data every 2 seconds from [PerfRadar].
class PerfRadarScreen extends StatefulWidget {
  const PerfRadarScreen({super.key, this.onClose});

  /// Called when the user taps the leading close button.
  final VoidCallback? onClose;

  @override
  State<PerfRadarScreen> createState() => _PerfRadarScreenState();
}

class _PerfRadarScreenState extends State<PerfRadarScreen> {
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0a0d0e),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0c1012),
          foregroundColor: const Color(0xFFe7eef0),
          elevation: 0,
          leading: widget.onClose != null
              ? IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFFe7eef0)),
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                )
              : null,
          title: const Text(
            'Perf Radar',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFe7eef0),
            ),
          ),
          bottom: const TabBar(
            labelColor: Color(0xFF2fe39b),
            unselectedLabelColor: Color(0xFF7d8e94),
            indicatorColor: Color(0xFF2fe39b),
            tabs: [
              Tab(text: 'Spans'),
              Tab(text: 'Frames'),
              Tab(text: 'Stability'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SpanStatsTable(snapshot: PerfRadar.snapshot()),
            FrameStatsPanel(stats: _frameStats),
            StabilityPanel(stability: _stability),
          ],
        ),
      ),
    );
  }
}
