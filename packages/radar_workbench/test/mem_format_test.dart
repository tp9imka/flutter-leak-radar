import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  group('originOf', () {
    const projectPackages = {'my_app'};

    test('null libraryUri maps to unknown', () {
      expect(
        originOf(null, projectPackages: projectPackages),
        RadarOrigin.unknown,
      );
    });

    test('dart: scheme maps to sdk', () {
      expect(
        originOf(Uri.parse('dart:core'), projectPackages: projectPackages),
        RadarOrigin.sdk,
      );
    });

    test('flutter framework package maps to framework', () {
      expect(
        originOf(
          Uri.parse('package:flutter/widgets.dart'),
          projectPackages: projectPackages,
        ),
        RadarOrigin.framework,
      );
    });

    test('package in projectPackages maps to project', () {
      expect(
        originOf(
          Uri.parse('package:my_app/main.dart'),
          projectPackages: projectPackages,
        ),
        RadarOrigin.project,
      );
    });

    test('package not in project or framework sets maps to dependency', () {
      expect(
        originOf(
          Uri.parse('package:collection/collection.dart'),
          projectPackages: projectPackages,
        ),
        RadarOrigin.dependency,
      );
    });

    test('malformed package: URI maps to unknown', () {
      expect(
        originOf(Uri.parse('package:'), projectPackages: projectPackages),
        RadarOrigin.unknown,
      );
    });

    test('other scheme maps to unknown', () {
      expect(
        originOf(
          Uri.parse('file:///tmp/foo.dart'),
          projectPackages: projectPackages,
        ),
        RadarOrigin.unknown,
      );
    });
  });

  group('packageLabelOf', () {
    test('null libraryUri returns null', () {
      expect(packageLabelOf(null), isNull);
    });

    test('package: URI returns the package name', () {
      expect(
        packageLabelOf(Uri.parse('package:livekit_client/room.dart')),
        'livekit_client',
      );
    });

    test('dart: URI returns dart:<lib>', () {
      expect(packageLabelOf(Uri.parse('dart:core')), 'dart:core');
    });

    test('malformed package: URI returns null', () {
      expect(packageLabelOf(Uri.parse('package:')), isNull);
    });

    test('other scheme returns null', () {
      expect(packageLabelOf(Uri.parse('file:///tmp/foo.dart')), isNull);
    });
  });
}
