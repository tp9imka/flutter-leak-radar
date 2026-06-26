import '../model/span.dart';

/// Bounded retention buffer for the slowest-N exemplar [Span]s.
///
/// Retains the globally slowest [capacity] spans seen so far, not just
/// the most recent. When full, a new span replaces the current minimum
/// only if it is slower. Memory is bounded at O([capacity]) spans.
///
/// Each [offer] call is O([capacity]) — acceptable for small capacities
/// (default 16, max recommended 64).
final class OutlierRing {
  final int capacity;

  final List<Span> _spans;
  int _offeredCount = 0;

  OutlierRing({this.capacity = 16})
      : assert(capacity > 0, 'capacity must be > 0'),
        _spans = [];

  /// Total number of spans offered, including those not retained.
  int get offeredCount => _offeredCount;

  /// Number of spans currently retained.
  int get count => _spans.length;

  /// A snapshot of retained spans, sorted slowest-first.
  ///
  /// The returned list is a fresh copy — mutations do not affect
  /// this ring.
  List<Span> get spans {
    final copy = List<Span>.of(_spans);
    copy.sort(
      (a, b) => b.durationMicros.compareTo(a.durationMicros),
    );
    return copy;
  }

  /// Offers [span] for retention.
  ///
  /// If the ring is below capacity, the span is retained. If full,
  /// the span replaces the current minimum only when its
  /// [Span.durationMicros] exceeds that minimum.
  void offer(Span span) {
    _offeredCount++;
    if (_spans.length < capacity) {
      _spans.add(span);
      return;
    }
    // Find index of minimum duration in the ring.
    var minIdx = 0;
    for (var i = 1; i < _spans.length; i++) {
      if (_spans[i].durationMicros < _spans[minIdx].durationMicros) {
        minIdx = i;
      }
    }
    if (span.durationMicros > _spans[minIdx].durationMicros) {
      _spans[minIdx] = span;
    }
  }
}
