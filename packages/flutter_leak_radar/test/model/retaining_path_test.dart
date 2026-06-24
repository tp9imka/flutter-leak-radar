// test/model/retaining_path_test.dart
import 'package:flutter_leak_radar/src/model/retaining_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hop1 = RetainingHop(objectType: 'Foo', field: 'bar');
  const hop2 = RetainingHop(objectType: 'Baz');

  test(
    'RetainingPathView: equal gcRootType + equal elements → == with equal hashCodes',
    () {
      final a = RetainingPathView(
        gcRootType: 'isolate',
        elements: [hop1, hop2],
      );
      final b = RetainingPathView(
        gcRootType: 'isolate',
        elements: [hop1, hop2],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    },
  );

  test('RetainingPathView: different elements → not equal', () {
    final a = RetainingPathView(gcRootType: 'isolate', elements: [hop1]);
    final b = RetainingPathView(gcRootType: 'isolate', elements: [hop2]);
    expect(a, isNot(equals(b)));
  });

  test('RetainingPathView.toJson omits gcRootType when null', () {
    final view = RetainingPathView(elements: [hop1]);
    final json = view.toJson();
    expect(json.containsKey('gcRootType'), isFalse);
  });

  test('RetainingPathView.toJson includes gcRootType when set', () {
    final view = RetainingPathView(gcRootType: 'isolate', elements: [hop1]);
    final json = view.toJson();
    expect(json['gcRootType'], 'isolate');
  });
}
