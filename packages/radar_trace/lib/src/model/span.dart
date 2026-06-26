import 'dart:collection';

import 'package:meta/meta.dart';

/// The completion status of a recorded [Span].
enum SpanStatus {
  /// The operation completed without error.
  ok,

  /// The operation threw an exception.
  error,

  /// The operation was explicitly cancelled before completion.
  cancelled,
}

/// Sentinel object used to distinguish "not passed" from `null`
/// in [Span.copyWith] for the nullable [parentId] parameter.
const Object _absentSpanId = _AbsentSpanId();

final class _AbsentSpanId {
  const _AbsentSpanId();
}

/// Opaque, value-typed span identifier backed by a monotonically
/// increasing integer.
///
/// Use [SpanId.generate] to mint a new unique id. Equality and
/// hashing are value-based so ids can be used as map keys.
@immutable
final class SpanId {
  final int _value;

  const SpanId(int value) : _value = value;

  static int _counter = 0;

  /// Mints a new unique [SpanId].
  ///
  /// Not cryptographically random — intended for correlation within
  /// a single process run, not for external export identifiers.
  static SpanId generate() => SpanId(++_counter);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SpanId && _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'SpanId($_value)';
}

/// An immutable record of one measured operation.
///
/// Timing is expressed in monotonic microseconds produced by a
/// [Stopwatch] — never wall-clock [DateTime], which is subject to
/// NTP and suspend skew.
///
/// [attributes] is a defensive, unmodifiable copy of the map passed
/// at construction time.
@immutable
final class Span {
  /// Unique identifier for this span.
  final SpanId spanId;

  /// Parent span id, or null if this is the root of a trace.
  final SpanId? parentId;

  /// Root span id of the trace tree this span belongs to.
  ///
  /// Equal to [spanId] when [parentId] is null.
  final SpanId traceId;

  /// Structured operation name (e.g. `'db.query.rooms'`).
  final String name;

  /// Optional category for grouping (e.g. `'db'`, `'http'`, `'ui'`).
  final String? category;

  /// Monotonic start time in microseconds from an arbitrary epoch.
  final int startMicros;

  /// Duration in microseconds; always >= 0.
  final int durationMicros;

  /// Whether the operation succeeded, threw, or was cancelled.
  final SpanStatus status;

  /// Typed, bounded, unmodifiable key/value attributes.
  final Map<String, Object?> attributes;

  /// Creates a [Span] with all required fields.
  ///
  /// [attributes] is defensively copied and wrapped in an
  /// [UnmodifiableMapView] — mutations to the original map after
  /// construction do not affect the span.
  Span({
    required this.spanId,
    required this.parentId,
    required this.traceId,
    required this.name,
    required this.category,
    required this.startMicros,
    required this.durationMicros,
    required this.status,
    required Map<String, Object?> attributes,
  }) : attributes = UnmodifiableMapView(Map<String, Object?>.of(attributes));

  /// Returns a copy of this span with the given fields replaced.
  ///
  /// To clear [parentId] to null, explicitly pass `parentId: null`.
  /// Due to the nullable type, `_absentSpanId` is used as a sentinel to
  /// distinguish between "not passed" and "passed as null".
  Span copyWith({
    SpanId? spanId,
    Object? parentId = _absentSpanId,
    SpanId? traceId,
    String? name,
    String? category,
    int? startMicros,
    int? durationMicros,
    SpanStatus? status,
    Map<String, Object?>? attributes,
  }) => Span(
    spanId: spanId ?? this.spanId,
    parentId: identical(parentId, _absentSpanId)
        ? this.parentId
        : parentId as SpanId?,
    traceId: traceId ?? this.traceId,
    name: name ?? this.name,
    category: category ?? this.category,
    startMicros: startMicros ?? this.startMicros,
    durationMicros: durationMicros ?? this.durationMicros,
    status: status ?? this.status,
    attributes: attributes ?? this.attributes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Span &&
          spanId == other.spanId &&
          parentId == other.parentId &&
          traceId == other.traceId &&
          name == other.name &&
          category == other.category &&
          startMicros == other.startMicros &&
          durationMicros == other.durationMicros &&
          status == other.status &&
          _mapEquals(attributes, other.attributes);

  @override
  int get hashCode => Object.hash(
    spanId,
    parentId,
    traceId,
    name,
    category,
    startMicros,
    durationMicros,
    status,
    Object.hashAll(
      (attributes.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map(
        (e) => Object.hash(e.key, e.value),
      ),
    ),
  );

  @override
  String toString() =>
      'Span(id=$spanId, name=$name, status=$status, '
      'dur=$durationMicrosµs)';
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
