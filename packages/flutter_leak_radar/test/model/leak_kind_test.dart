import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeakKind', () {
    test('contains retainedByNonLiveRoot', () {
      expect(LeakKind.values, contains(LeakKind.retainedByNonLiveRoot));
    });

    test('retainedByNonLiveRoot has a non-empty name', () {
      expect(LeakKind.retainedByNonLiveRoot.name, isNotEmpty);
    });
  });
}
