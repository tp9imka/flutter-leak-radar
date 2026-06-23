import 'package:meta/meta.dart';

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
}

@immutable
final class RetainingPathView {
  const RetainingPathView({required this.elements, this.gcRootType});

  final String? gcRootType;
  final List<RetainingHop> elements;

  Map<String, Object?> toJson() => {
        'gcRootType': gcRootType,
        'elements': elements.map((e) => e.toJson()).toList(),
      };
}
