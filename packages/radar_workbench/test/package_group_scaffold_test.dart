import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// Minimal row fixture: a declared library, an optional anchor library, and a
/// byte + delta metric.
typedef _Row = ({
  String name,
  Uri? declared,
  Uri? anchor,
  int bytes,
  int delta,
});

_Row _row(
  String name, {
  String? declared,
  String? anchor,
  int bytes = 0,
  int delta = 0,
}) => (
  name: name,
  declared: declared == null ? null : Uri.parse(declared),
  anchor: anchor == null ? null : Uri.parse(anchor),
  bytes: bytes,
  delta: delta,
);

List<PackageGroup<_Row>> _group(
  List<_Row> rows, {
  Set<String> projectPackages = const {'my_app'},
}) => groupRowsByPackage<_Row>(
  rows,
  declaredLibraryOf: (r) => r.declared,
  anchorLibraryOf: (r) => r.anchor,
  bytesOf: (r) => r.bytes,
  deltaOf: (r) => r.delta,
  projectPackages: projectPackages,
);

void main() {
  group('groupRowsByPackage', () {
    test('pins the project group first and the runtime group last', () {
      final groups = _group([
        _row('A', declared: 'package:my_app/a.dart', bytes: 100, delta: 100),
        _row('B', declared: 'package:livekit/b.dart', bytes: 50, delta: 50),
        _row('C', declared: 'package:flutter/c.dart', bytes: 30, delta: 30),
        _row('D', declared: 'dart:core', bytes: 20, delta: 20),
      ]);

      expect(groups.first.isProject, isTrue);
      expect(groups.first.package, 'my_app');
      expect(groups.last.isRuntime, isTrue);
      expect(groups.last.package, 'runtime');
      // The middle group is the dependency.
      expect(groups[1].package, 'livekit');
      expect(groups[1].origin, RadarOrigin.dependency);
    });

    test('merges framework and sdk rows into one runtime group', () {
      final groups = _group([
        _row('C', declared: 'package:flutter/c.dart', bytes: 30, delta: 30),
        _row('D', declared: 'dart:core', bytes: 20, delta: 20),
      ]);

      expect(groups, hasLength(1));
      final runtime = groups.single;
      expect(runtime.isRuntime, isTrue);
      expect(runtime.rows, hasLength(2));
      expect(runtime.totalBytes, 50);
      expect(runtime.totalDelta, 50);
    });

    test('anchor library wins over the declared library', () {
      // Declared in the SDK, but anchored (retained) by app code: it belongs
      // to the project group, not runtime.
      final groups = _group([
        _row(
          'X',
          declared: 'dart:async',
          anchor: 'package:my_app/x.dart',
          bytes: 10,
          delta: 10,
        ),
      ]);

      expect(groups.single.isProject, isTrue);
      expect(groups.single.package, 'my_app');
    });

    test('a row with no anchor groups under its declared package', () {
      final groups = _group([
        _row('Y', declared: 'package:my_app/y.dart', bytes: 10, delta: 10),
      ]);

      expect(groups.single.package, 'my_app');
      expect(groups.single.isProject, isTrue);
    });

    test('sorts rows within a group by metric descending', () {
      final groups = _group([
        _row('small', declared: 'package:my_app/a.dart', delta: 10),
        _row('big', declared: 'package:my_app/b.dart', delta: 900),
        _row('mid', declared: 'package:my_app/c.dart', delta: 100),
      ]);

      expect(groups.single.rows.map((r) => r.name), ['big', 'mid', 'small']);
      expect(groups.single.totalDelta, 1010);
    });

    test('unresolved package falls under the (unknown) group', () {
      final groups = _group([_row('Z', bytes: 5, delta: 5)]);

      expect(groups.single.package, '(unknown)');
      expect(groups.single.origin, RadarOrigin.unknown);
    });

    test('without deltaOf, ordering and totals use bytes', () {
      final groups = groupRowsByPackage<_Row>(
        [
          _row('A', declared: 'package:my_app/a.dart', bytes: 100),
          _row('B', declared: 'package:livekit/b.dart', bytes: 300),
        ],
        declaredLibraryOf: (r) => r.declared,
        anchorLibraryOf: (r) => r.anchor,
        bytesOf: (r) => r.bytes,
        projectPackages: const {'my_app'},
      );

      // Project still pinned first even though the dependency is larger.
      expect(groups.first.package, 'my_app');
      expect(groups.first.totalBytes, 100);
      expect(groups.first.totalDelta, 0);
      expect(groups[1].totalBytes, 300);
    });
  });
}
