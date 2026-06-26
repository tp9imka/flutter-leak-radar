import 'package:meta/meta.dart';

/// Composite key that identifies an aggregate series in a TraceRecorder.
///
/// Spans with the same [name] and [category] are bucketed together.
@immutable
final class TraceKey {
  /// Structured operation name (e.g. `'db.query.rooms'`).
  final String name;

  /// Optional category (e.g. `'db'`, `'http'`). Null is a valid value
  /// and differs from any non-null category.
  final String? category;

  /// Creates a [TraceKey] with the given [name] and optional [category].
  ///
  /// This constructor is `const`-constructible.
  const TraceKey({required this.name, required this.category});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceKey &&
          name == other.name &&
          category == other.category;

  @override
  int get hashCode => Object.hash(name, category);

  @override
  String toString() => category != null ? '$category/$name' : name;
}
