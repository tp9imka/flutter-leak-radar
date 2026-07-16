import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  group('OriginClassifier.classify', () {
    const classifier = OriginClassifier(projectPackages: {'my_app'});

    test('dart: scheme → dartSdk', () {
      expect(classifier.classify(Uri.parse('dart:core')), ClassOrigin.dartSdk);
    });

    test('package: in kFlutterFrameworkPackages → flutterFramework', () {
      expect(
        classifier.classify(Uri.parse('package:flutter/widgets.dart')),
        ClassOrigin.flutterFramework,
      );
    });

    test('package: in projectPackages → project', () {
      expect(
        classifier.classify(Uri.parse('package:my_app/main.dart')),
        ClassOrigin.project,
      );
    });

    test('package: not in project or framework sets → dependency', () {
      expect(
        classifier.classify(Uri.parse('package:collection/collection.dart')),
        ClassOrigin.dependency,
      );
    });

    test('empty Uri() placeholder → unknown', () {
      expect(classifier.classify(Uri()), ClassOrigin.unknown);
    });

    test('other scheme → unknown', () {
      expect(
        classifier.classify(Uri.parse('file:///tmp/foo.dart')),
        ClassOrigin.unknown,
      );
    });

    test('malformed package: URI with no segments → unknown', () {
      expect(classifier.classify(Uri.parse('package:')), ClassOrigin.unknown);
    });
  });

  group('OriginClassifier.packageOf', () {
    const classifier = OriginClassifier(projectPackages: {'my_app'});

    test('package:foo/bar.dart → foo', () {
      expect(classifier.packageOf(Uri.parse('package:foo/bar.dart')), 'foo');
    });

    test('dart:core → dart:core', () {
      expect(classifier.packageOf(Uri.parse('dart:core')), 'dart:core');
    });

    test('Uri() → null', () {
      expect(classifier.packageOf(Uri()), isNull);
    });

    test('malformed package: URI with no segments → null', () {
      expect(classifier.packageOf(Uri.parse('package:')), isNull);
    });
  });

  group('kFlutterFrameworkPackages', () {
    test('contains the expected framework package names', () {
      expect(kFlutterFrameworkPackages, {
        'flutter',
        'flutter_test',
        'flutter_localizations',
        'flutter_driver',
        'flutter_web_plugins',
        'sky_engine',
      });
    });
  });
}
