// lib/src/ui/stability_view.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../model/error_record.dart';
import '../model/stall_record.dart';
import '../model/stability_snapshot.dart';
import '../facade/perf_radar.dart';
import 'stall_detail_screen.dart';
import 'dart:async';

// ── Sub-tab index ─────────────────────────────────────────────────────────────

enum _StabilitySubTab { errors, stalls }

// ── Constants ─────────────────────────────────────────────────────────────────

/// Duration threshold above which a stall row is shown amber (600ms).
const int _kStallAmberMicros = 600000;

/// Duration threshold above which a stall row is shown red (1 s).
const int _kStallRedMicros = 1000000;

/// Stall watchdog detection threshold shown in the header (250ms).
const int _kWatchdogThresholdMs = 250;

// ── Grouping helper ───────────────────────────────────────────────────────────

/// Groups a list of [ErrorRecord]s by (message, context) key.
///
/// Returns entries sorted by the active [_ErrorSort] order.
List<_ErrorGroup> _groupErrors(List<ErrorRecord> records, _ErrorSort sort) {
  final map = <String, _ErrorGroup>{};
  for (final r in records) {
    final key = '${r.context ?? ''}\x00${r.message}';
    final existing = map[key];
    if (existing == null) {
      map[key] = _ErrorGroup(
        message: r.message,
        context: r.context,
        repeats: 1,
        lastSeenMicros: r.clockMicros,
        lastStackTrace: r.stackTraceString,
      );
    } else {
      map[key] = existing.copyWith(
        repeats: existing.repeats + 1,
        lastSeenMicros: math.max(existing.lastSeenMicros, r.clockMicros),
        lastStackTrace: r.stackTraceString ?? existing.lastStackTrace,
      );
    }
  }
  final groups = map.values.toList();
  switch (sort) {
    case _ErrorSort.repeats:
      groups.sort((a, b) => b.repeats.compareTo(a.repeats));
    case _ErrorSort.time:
      groups.sort((a, b) => b.lastSeenMicros.compareTo(a.lastSeenMicros));
  }
  return groups;
}

// ── Value types ───────────────────────────────────────────────────────────────

enum _ErrorSort { repeats, time }

/// Aggregated group of errors sharing the same (message, context) identity.
final class _ErrorGroup {
  const _ErrorGroup({
    required this.message,
    required this.context,
    required this.repeats,
    required this.lastSeenMicros,
    required this.lastStackTrace,
  });

  final String message;
  final String? context;
  final int repeats;
  final int lastSeenMicros;
  final String? lastStackTrace;

  _ErrorGroup copyWith({
    int? repeats,
    int? lastSeenMicros,
    String? lastStackTrace,
  }) => _ErrorGroup(
    message: message,
    context: context,
    repeats: repeats ?? this.repeats,
    lastSeenMicros: lastSeenMicros ?? this.lastSeenMicros,
    lastStackTrace: lastStackTrace ?? this.lastStackTrace,
  );
}

// ── Public embed widget ───────────────────────────────────────────────────────

/// Tabbed body view of the Stability inspector.
///
/// Renders two sub-tabs — Errors · Stalls — with full grouping, sort,
/// and drill-down to stack traces.
///
/// No [Scaffold] — designed to be embedded inside a containing
/// [Scaffold], for example in [StabilityScreen] or the umbrella
/// combined-radar screen.
///
/// Refreshes data from [PerfRadar] every two seconds.
class StabilityView extends StatefulWidget {
  /// Creates a [StabilityView].
  const StabilityView({super.key});

  @override
  State<StabilityView> createState() => _StabilityViewState();
}

class _StabilityViewState extends State<StabilityView> {
  late StabilitySnapshot _snapshot;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _snapshot = PerfRadar.stabilitySnapshot;
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() => _snapshot = PerfRadar.stabilitySnapshot);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StabilityViewBody(snapshot: _snapshot);
  }
}

// ── Testable snapshot-driven body ─────────────────────────────────────────────

/// The stability inspector body driven by a fixed [snapshot].
///
/// [StabilityView] refreshes this on a two-second timer using live data
/// from [PerfRadar]. Expose this widget directly for tests that need to
/// inject a controlled [StabilitySnapshot] without starting the engine.
class StabilityViewBody extends StatefulWidget {
  /// Creates a [StabilityViewBody] from [snapshot].
  const StabilityViewBody({super.key, required this.snapshot});

  /// The stability data to render.
  final StabilitySnapshot snapshot;

  @override
  State<StabilityViewBody> createState() => _StabilityViewBodyState();
}

class _StabilityViewBodyState extends State<StabilityViewBody> {
  _StabilitySubTab _activeTab = _StabilitySubTab.errors;
  _ErrorSort _errorSort = _ErrorSort.repeats;

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
      _StabilitySubTab.errors => _ErrorsTab(
        snapshot: widget.snapshot,
        sort: _errorSort,
        onSortChanged: (s) => setState(() => _errorSort = s),
      ),
      _StabilitySubTab.stalls => _StallsTab(snapshot: widget.snapshot),
    };
  }
}

// ── Sub-tab bar ───────────────────────────────────────────────────────────────

class _SubTabBar extends StatelessWidget {
  const _SubTabBar({required this.active, required this.onSelect});

  final _StabilitySubTab active;
  final ValueChanged<_StabilitySubTab> onSelect;

  static const _labels = {
    _StabilitySubTab.errors: 'Errors',
    _StabilitySubTab.stalls: 'Stalls',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RadarColors.bgPanel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _StabilitySubTab.values.map((tab) {
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
        padding: const EdgeInsets.symmetric(
          horizontal: RadarDensity.chipHPad,
          vertical: RadarDensity.chipVPad,
        ),
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

// ── Errors tab ────────────────────────────────────────────────────────────────

class _ErrorsTab extends StatelessWidget {
  const _ErrorsTab({
    required this.snapshot,
    required this.sort,
    required this.onSortChanged,
  });

  final StabilitySnapshot snapshot;
  final _ErrorSort sort;
  final ValueChanged<_ErrorSort> onSortChanged;

  String get _sortLabel => switch (sort) {
    _ErrorSort.repeats => 'repeats',
    _ErrorSort.time => 'time',
  };

  @override
  Widget build(BuildContext context) {
    final groups = _groupErrors(snapshot.recentErrors, sort);
    final distinct = groups.length;
    final total = snapshot.errorCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Summary + sort toggle ────────────────────────────────────────
        _TabHeader(
          left: '$distinct distinct · $total total',
          actionLabel: _sortLabel,
          onActionTap: () {
            final next = switch (sort) {
              _ErrorSort.repeats => _ErrorSort.time,
              _ErrorSort.time => _ErrorSort.repeats,
            };
            onSortChanged(next);
          },
        ),
        const Divider(height: 1, thickness: 1, color: RadarColors.hairline08),
        // ── List or empty state ──────────────────────────────────────────
        Expanded(
          child: groups.isEmpty
              ? const _EmptyState(
                  icon: Icons.check_circle_outline,
                  message: 'No errors captured.',
                  sub:
                      'Errors are recorded when '
                      'FlutterError.onError fires.',
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    8 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, i) => _ErrorRow(
                    group: groups[i],
                    onTap: () => _openDetail(context, groups[i]),
                  ),
                ),
        ),
      ],
    );
  }

  void _openDetail(BuildContext context, _ErrorGroup group) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ErrorDetailScreen(group: group),
        fullscreenDialog: false,
      ),
    );
  }
}

// ── Error row ─────────────────────────────────────────────────────────────────

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.group, required this.onTap});

  final _ErrorGroup group;
  final VoidCallback onTap;

  /// Formats a monotonic clock value as a compact relative time string.
  ///
  /// The watchdog timestamps are from [Timeline.now] (monotonic micros
  /// since process start), not wall-clock time, so we display them as
  /// a session-relative offset rather than a wall-clock time.
  String _formatTime(int clockMicros) {
    final ms = clockMicros ~/ 1000;
    if (ms < 1000) return '${ms}ms';
    final s = ms / 1000;
    if (s < 60) return '${s.toStringAsFixed(1)}s';
    final m = s ~/ 60;
    return '${m}m ${(s % 60).toStringAsFixed(0)}s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: RadarColors.bgSurface,
          borderRadius: RadarDensity.rowRadius,
          border: Border.all(color: RadarColors.hairline08),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Red left bar
              Container(
                width: RadarDensity.severityBarWidth,
                decoration: const BoxDecoration(
                  color: RadarColors.critical,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(11),
                    bottomLeft: Radius.circular(11),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Message (up to 2 lines)
                      Text(
                        group.message,
                        style: RadarTypography.monoBody,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Type tag · time · ×repeats
                      Row(
                        children: [
                          if (group.context != null) ...[
                            RadarTag(
                              label: group.context!,
                              color: RadarColors.warning,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _formatTime(group.lastSeenMicros),
                            style: RadarTypography.monoLabel,
                          ),
                          const Spacer(),
                          Text(
                            '×${group.repeats}',
                            style: RadarTypography.monoNumber.copyWith(
                              color: RadarColors.critical,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '›',
                            style: RadarTypography.monoBody.copyWith(
                              color: RadarColors.text40,
                            ),
                          ),
                        ],
                      ),
                    ],
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

// ── Error detail screen ───────────────────────────────────────────────────────

class _ErrorDetailScreen extends StatelessWidget {
  const _ErrorDetailScreen({required this.group});

  final _ErrorGroup group;

  @override
  Widget build(BuildContext context) {
    final frames = _parseFrames(group.lastStackTrace);

    return Scaffold(
      backgroundColor: RadarColors.bgPage,
      appBar: AppBar(
        backgroundColor: RadarColors.bgPanel,
        foregroundColor: RadarColors.text100,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: RadarColors.text100),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          group.context ?? 'Error',
          style: RadarTypography.appBarTitle,
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // Error card
          _ErrorDetailCard(group: group),
          const SizedBox(height: 12),
          // Stack trace
          if (frames.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('STACK TRACE', style: RadarTypography.monoLabel),
            ),
            _StackTraceCard(frames: frames),
          ] else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: RadarColors.bgSurface,
                borderRadius: RadarDensity.rowRadius,
                border: Border.all(color: RadarColors.hairline08),
              ),
              child: Text(
                'No stack trace captured.',
                style: RadarTypography.monoLabel,
              ),
            ),
        ],
      ),
    );
  }

  List<String> _parseFrames(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
  }
}

class _ErrorDetailCard extends StatelessWidget {
  const _ErrorDetailCard({required this.group});

  final _ErrorGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.rowRadius,
        border: Border.all(color: Color.fromRGBO(255, 93, 108, 0.25)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: RadarDensity.severityBarWidth,
              decoration: const BoxDecoration(
                color: RadarColors.critical,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(11),
                  bottomLeft: Radius.circular(11),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (group.context != null) ...[
                      RadarTag(
                        label: group.context!,
                        color: RadarColors.warning,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(group.message, style: RadarTypography.monoBody),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '×${group.repeats}',
                          style: RadarTypography.monoNumber.copyWith(
                            color: RadarColors.critical,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('occurrences', style: RadarTypography.monoLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StackTraceCard extends StatelessWidget {
  const _StackTraceCard({required this.frames});

  final List<String> frames;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarColors.bgCode,
        borderRadius: RadarDensity.rowRadius,
        border: Border.all(color: RadarColors.hairline08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: frames.map((f) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(f, style: RadarTypography.monoCode, softWrap: true),
          );
        }).toList(),
      ),
    );
  }
}

// ── Stalls tab ────────────────────────────────────────────────────────────────

class _StallsTab extends StatelessWidget {
  const _StallsTab({required this.snapshot});

  final StabilitySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final stalls = snapshot.recentStalls.reversed.toList();
    final total = snapshot.stallCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabHeader(
          left:
              '$total stalls > ${_kWatchdogThresholdMs}ms'
              ' · main-thread watchdog',
        ),
        const Divider(height: 1, thickness: 1, color: RadarColors.hairline08),
        Expanded(
          child: stalls.isEmpty
              ? const _EmptyState(
                  icon: Icons.timer_off_outlined,
                  message: 'No stalls detected.',
                  sub:
                      'Stalls > ${_kWatchdogThresholdMs}ms are '
                      'recorded by the watchdog.',
                )
              : _StallsList(stalls: stalls),
        ),
      ],
    );
  }
}

class _StallsList extends StatelessWidget {
  const _StallsList({required this.stalls});

  final List<StallRecord> stalls;

  @override
  Widget build(BuildContext context) {
    // Longest stall sets 100% bar width.
    final maxDuration = stalls.fold(0, (m, s) => math.max(m, s.durationMicros));

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: stalls.length,
      itemBuilder: (context, i) =>
          _StallRow(stall: stalls[i], maxDurationMicros: maxDuration),
    );
  }
}

class _StallRow extends StatelessWidget {
  const _StallRow({required this.stall, required this.maxDurationMicros});

  final StallRecord stall;
  final int maxDurationMicros;

  Color get _durationColor {
    if (stall.durationMicros >= _kStallRedMicros) return RadarColors.critical;
    if (stall.durationMicros >= _kStallAmberMicros) return RadarColors.warning;
    return RadarColors.text60;
  }

  String get _durationLabel {
    final ms = stall.durationMicros / 1000;
    if (ms >= 1000) {
      return '${(ms / 1000).toStringAsFixed(2)}s';
    }
    return '${ms.toStringAsFixed(1)}ms';
  }

  String _formatTime(int clockMicros) {
    final ms = clockMicros ~/ 1000;
    if (ms < 1000) return '${ms}ms';
    final s = ms / 1000;
    if (s < 60) return '${s.toStringAsFixed(1)}s';
    final m = s ~/ 60;
    return '${m}m ${(s % 60).toStringAsFixed(0)}s';
  }

  /// Opens the detail screen, correlating this stall with the slowest retained
  /// spans from the live trace snapshot (empty/no-op when no engine is active).
  void _openDetail(BuildContext context) {
    final spans = [
      for (final s in PerfRadar.snapshot().stats.values) ...s.outliers,
    ];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StallDetailScreen(stall: stall, candidateSpans: spans),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final barFraction = maxDurationMicros > 0
        ? stall.durationMicros / maxDurationMicros
        : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: RadarDensity.rowRadius,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: RadarColors.bgSurface,
            borderRadius: RadarDensity.rowRadius,
            border: Border.all(color: RadarColors.hairline08),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Duration (color-graded, mono, prominent)
                  Text(
                    _durationLabel,
                    style: radarMonoStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _durationColor,
                    ),
                  ),
                  const Spacer(),
                  // Session-relative time of detection
                  Text(
                    _formatTime(stall.clockMicros),
                    style: RadarTypography.monoLabel,
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: RadarColors.text40,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Proportional duration bar
              LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    height: 3,
                    width: constraints.maxWidth,
                    decoration: BoxDecoration(
                      color: RadarColors.hairline08,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: barFraction.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _durationColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

/// Compact header row shared by both sub-tabs.
class _TabHeader extends StatelessWidget {
  const _TabHeader({required this.left, this.actionLabel, this.onActionTap});

  final String left;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(left, style: RadarTypography.monoLabel)),
          if (actionLabel != null && onActionTap != null)
            GestureDetector(
              onTap: onActionTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: RadarColors.bgInput,
                  borderRadius: RadarDensity.tagRadius,
                  border: Border.all(color: RadarColors.hairline09),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: RadarTypography.monoLabel.copyWith(
                        color: RadarColors.text60,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.swap_vert,
                      size: 11,
                      color: RadarColors.text40,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Centered empty-state widget shared by both sub-tabs.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.sub,
  });

  final IconData icon;
  final String message;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: RadarColors.text15),
            const SizedBox(height: 12),
            Text(
              message,
              style: RadarTypography.monoBody.copyWith(
                color: RadarColors.text60,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              sub,
              style: RadarTypography.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
