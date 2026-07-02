import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// Multi-dump trend: plot one class's instance count across the selected dumps
/// over time. The soak-test view — a class climbing and never returning to
/// baseline is the classic slow leak.
class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  String? _class;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) {
        final wc = widget.workspace;
        final selected = [
          for (final s in wc.memory.snapshots)
            if (wc.trendSelection.contains(s.id)) s,
        ];
        if (selected.length < 2) {
          return Center(
            child: Text(
              'Select at least two dumps in the workspace to plot a trend.',
              style: RadarTypography.monoLabel,
            ),
          );
        }
        final growing = growingClassNames(selected);
        final klass = _class ?? (growing.isNotEmpty ? growing.first : null);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Trends', style: RadarTypography.appBarTitle),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in growing)
                    RadarFilterChip(
                      label: name,
                      selected: name == klass,
                      onSelected: () => setState(() => _class = name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (klass != null) ...[
                Builder(
                  builder: (context) {
                    final series = computeTrend(selected, klass);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$klass · first → last',
                              style: RadarTypography.monoLabel,
                            ),
                            const Spacer(),
                            Text(
                              '${series.netInstanceDelta >= 0 ? '+' : ''}'
                              '${series.netInstanceDelta} instances',
                              style: RadarTypography.metricValue.copyWith(
                                color: series.netInstanceDelta >= 0
                                    ? RadarColors.critical
                                    : RadarColors.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        RadarTrendChart(
                          series: [
                            for (final p in series.points) p.instanceCount,
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
