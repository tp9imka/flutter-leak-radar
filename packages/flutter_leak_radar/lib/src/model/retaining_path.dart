import 'package:flutter/foundation.dart';

/// One hop in a retaining path (UI-facing copy, decoupled from vm_service types).
@immutable
final class RetainingHop {
  const RetainingHop({required this.objectType, this.field, this.index, this.mapKey});

  final String objectType;
  final String? field;
  final int? index;
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

@immutable
final class RetainingPathView {
  const RetainingPathView({required this.elements, this.gcRootType});

  final String? gcRootType;
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
