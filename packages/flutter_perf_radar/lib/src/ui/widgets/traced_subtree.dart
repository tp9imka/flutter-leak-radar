import 'package:flutter/widgets.dart';

import '../../facade/perf_radar.dart';

/// Wraps [child] and counts how many times the subtree rebuilds.
///
/// Each rebuild increments a counter recorded via [PerfRadar.trace] under
/// `rebuild:<label>`. When [PerfRadar] is disabled (no active engine), the
/// widget is a transparent pass-through with zero overhead — [PerfRadar.trace]
/// calls the body directly and records nothing.
///
/// The rebuild count is exposed through the span system as
/// [SpanKeyStatsSnapshot.count] on the key `rebuild:<label>`. Duration
/// values in that snapshot reflect the cost of incrementing the counter
/// (nanoseconds), not widget build time — the meaningful signal is count.
///
/// Example:
///
/// ```dart
/// TracedSubtree(
///   label: 'home_feed',
///   child: HomeFeed(),
/// )
/// ```
class TracedSubtree extends StatefulWidget {
  /// Creates a [TracedSubtree].
  const TracedSubtree({super.key, required this.label, required this.child});

  /// Unique label for this subtree.
  ///
  /// Becomes the span key `rebuild:<label>` in [PerfRadar].
  final String label;

  /// The child subtree to render and count rebuilds for.
  final Widget child;

  @override
  State<TracedSubtree> createState() => _TracedSubtreeState();
}

class _TracedSubtreeState extends State<TracedSubtree> {
  int _rebuildCount = 0;

  @override
  Widget build(BuildContext context) {
    // Increment and record via the span system. PerfRadar.trace records a span
    // whose duration is the cost of this trivial lambda — near-zero µs. The
    // rebuild count is surfaced through SpanKeyStatsSnapshot.count, which
    // increments once per call. When no engine is active, this is a no-op.
    _rebuildCount++;
    PerfRadar.trace('rebuild:${widget.label}', () => _rebuildCount);
    return widget.child;
  }
}
