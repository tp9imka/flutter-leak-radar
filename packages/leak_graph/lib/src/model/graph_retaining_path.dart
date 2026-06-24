import 'root_kind.dart';

/// One step in a retaining path: the object class and optionally how it holds
/// the next object (field name or list index).
final class GraphHop {
  final String className;
  final String? field;
  final int? index;

  const GraphHop({required this.className, this.field, this.index});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphHop &&
          className == other.className &&
          field == other.field &&
          index == other.index;

  @override
  int get hashCode => Object.hash(className, field, index);

  Map<String, Object?> toJson() => {
    'className': className,
    if (field != null) 'field': field,
    if (index != null) 'index': index,
  };
}

/// The chain of objects from a GC root down to the suspected leaked object.
final class GraphRetainingPath {
  final List<GraphHop> hops;
  final RootKind rootKind;

  const GraphRetainingPath({required this.hops, required this.rootKind});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphRetainingPath &&
          rootKind == other.rootKind &&
          _listEquals(hops, other.hops);

  @override
  int get hashCode => Object.hash(rootKind, Object.hashAll(hops));

  Map<String, Object?> toJson() => {
    'rootKind': rootKind.name,
    'hops': [for (final h in hops) h.toJson()],
  };
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
