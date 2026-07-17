import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// Point-in-time diff of two dumps. Two dropdowns pick baseline (A) and
/// comparison (B); the selection is pushed into the workspace's `MemoryController`
/// (which computes the diff), and the reused `DiffTable` renders it.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  int? _a;
  int? _b;
  String? _selectedClass;

  WorkspaceController get _wc => widget.workspace;

  @override
  void initState() {
    super.initState();
    final ids = _wc.dumps.map((d) => d.id).toList();
    if (ids.length >= 2) {
      _a = ids[ids.length - 2];
      _b = ids.last;
      _apply();
    }
  }

  void _apply() {
    if (_a != null && _b != null && _a != _b) {
      _wc.selectComparePair(_a!, _b!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _wc.memory,
      builder: (context, _) {
        final dumps = _wc.dumps;
        final diff = _wc.memory.diff ?? const <ClassCountDiff>[];
        final comparison = _wc.memory.comparison;
        final triage = comparison == null
            ? const <String, TriageDisplay>{}
            : triageDisplayByClassName(
                comparison.analysisResult.clusters,
                _wc.triage,
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Text('Compare', style: RadarTypography.appBarTitle),
                  const SizedBox(width: 16),
                  _picker(
                    dumps,
                    _a,
                    (v) => setState(() {
                      _a = v;
                      _apply();
                    }),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16),
                  ),
                  _picker(
                    dumps,
                    _b,
                    (v) => setState(() {
                      _b = v;
                      _apply();
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: dumps.length < 2
                  ? Center(
                      child: Text(
                        'Load at least two dumps to compare.',
                        style: RadarTypography.monoLabel,
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: DiffTable(
                            diffs: diff,
                            absolute: false,
                            // Mirror the DevTools wiring so the S1 "which are
                            // MINE" grouping is live on desktop Compare too.
                            classAnchors: comparison == null
                                ? const {}
                                : classAnchorsFor(comparison.analysisResult),
                            projectPackages: comparison == null
                                ? const {}
                                : comparison.analysisResult.resolvedAppPackages
                                      .toSet(),
                            summary: const SizedBox.shrink(),
                            triage: triage,
                            selected: _selectedClass,
                            onSelected: (c) =>
                                setState(() => _selectedClass = c),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 340, child: _detailFor(_selectedClass)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailFor(String? className) {
    final comparison = _wc.memory.comparison;
    // The hop chips classify origin from the resolved project set — wire it at
    // every state so they agree with the diff row chips (never DEPENDENCY for a
    // class the row calls YOURS).
    final projectPackages = comparison == null
        ? const <String>{}
        : comparison.analysisResult.resolvedAppPackages.toSet();
    if (className == null || comparison == null) {
      return ClassDetailPanel(
        className: null,
        profile: null,
        projectPackages: projectPackages,
      );
    }
    ClassRootProfile? profile;
    for (final p in comparison.analysisResult.classRootProfiles) {
      if (p.className == className) {
        profile = p;
        break;
      }
    }
    ClassPathDistribution? dist;
    for (final d in comparison.analysisResult.classPathDistributions) {
      if (d.className == className) {
        dist = d;
        break;
      }
    }
    return ClassDetailPanel(
      className: className,
      profile: profile,
      distribution: dist,
      projectPackages: projectPackages,
      representativeAnchorHopIndex: representativeAnchorHopIndexFor(
        comparison.analysisResult,
        profile,
      ),
    );
  }

  Widget _picker(
    List<DumpMeta> dumps,
    int? value,
    ValueChanged<int?> onChanged,
  ) {
    return DropdownButton<int>(
      value: value,
      dropdownColor: RadarColors.bgSurface,
      style: RadarTypography.monoBody,
      items: [
        for (final d in dumps)
          DropdownMenuItem(value: d.id, child: Text(d.label)),
      ],
      onChanged: onChanged,
    );
  }
}
