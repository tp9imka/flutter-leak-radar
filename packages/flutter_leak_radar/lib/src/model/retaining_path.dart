import 'package:flutter/foundation.dart';

/// One hop in a retaining path.
///
/// A UI-facing value type, decoupled from `vm_service` internals. Each hop
/// describes one object in the chain from the GC root to the leaked object.
@immutable
final class RetainingHop {
  const RetainingHop({required this.objectType, this.field, this.index, this.mapKey});

  /// Runtime type name of the retaining object at this hop.
  final String objectType;

  /// Field name on [objectType] that holds the reference, if applicable.
  final String? field;

  /// List or array index at this hop, if applicable.
  final int? index;

  /// Map key at this hop, if applicable.
  final String? mapKey;

  Map<String, Object?> toJson() => {
        'objectType': objectType,
        if (field != null) 'field': field,
        if (index != null) 'index': index,
        if (mapKey != null) 'mapKey': mapKey,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetainingHop &&
          objectType == other.objectType &&
          field == other.field &&
          index == other.index &&
          mapKey == other.mapKey;

  @override
  int get hashCode => Object.hash(objectType, field, index, mapKey);
}

/// The full retaining path from a GC root to a leaked object.
///
/// Fetched on demand via [LeakRadar.fetchRetainingPath] and displayed in the
/// [LeakRadarScreen] when the user expands a finding tile.
@immutable
final class RetainingPathView {
  const RetainingPathView({required this.elements, this.gcRootType});

  /// GC root type description (e.g. `'class table'`), if reported by the VM.
  final String? gcRootType;

  /// Ordered list of hops from GC root (index 0) to the leaked object.
  final List<RetainingHop> elements;

  Map<String, Object?> toJson() => {
        if (gcRootType != null) 'gcRootType': gcRootType,
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetainingPathView &&
          gcRootType == other.gcRootType &&
          listEquals(elements, other.elements);

  @override
  int get hashCode => Object.hash(gcRootType, Object.hashAll(elements));
}
