// test/config/graph_scan_test.dart
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GraphScan defaults', () {
    test('everyNthNavigation defaults to 5', () {
      const g = GraphScan();
      expect(g.everyNthNavigation, 5);
    });

    test('maxGraphObjects defaults to 500000', () {
      const g = GraphScan();
      expect(g.maxGraphObjects, 500000);
    });

    test('appPackages defaults to empty', () {
      const g = GraphScan();
      expect(g.appPackages, isEmpty);
    });

    test('minClusterSize defaults to 2', () {
      const g = GraphScan();
      expect(g.minClusterSize, 2);
    });
  });

  group('GraphScan equality', () {
    test('two default instances are equal', () {
      const a = GraphScan();
      const b = GraphScan();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('instances differing by everyNthNavigation are not equal', () {
      const a = GraphScan(everyNthNavigation: 5);
      const b = GraphScan(everyNthNavigation: 10);
      expect(a == b, isFalse);
    });

    test('instances differing by maxGraphObjects are not equal', () {
      const a = GraphScan(maxGraphObjects: 500000);
      const b = GraphScan(maxGraphObjects: 100000);
      expect(a == b, isFalse);
    });

    test('instances differing by appPackages are not equal', () {
      const a = GraphScan(appPackages: ['com.example']);
      const b = GraphScan(appPackages: []);
      expect(a == b, isFalse);
    });

    test('instances with same appPackages list are equal', () {
      const a = GraphScan(appPackages: ['com.example', 'com.foo']);
      const b = GraphScan(appPackages: ['com.example', 'com.foo']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('instances differing by minClusterSize are not equal', () {
      const a = GraphScan(minClusterSize: 2);
      const b = GraphScan(minClusterSize: 5);
      expect(a == b, isFalse);
    });
  });
}
