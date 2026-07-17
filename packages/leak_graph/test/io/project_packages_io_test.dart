import 'dart:io';

import 'package:leak_graph/io.dart';
import 'package:test/test.dart';

void main() {
  group('packageNameFromPubspec', () {
    test('reads a top-level unquoted name', () {
      const yaml = 'name: my_app\ndescription: demo\n';
      expect(packageNameFromPubspec(yaml), 'my_app');
    });

    test('strips surrounding quotes', () {
      expect(packageNameFromPubspec('name: "my_app"\n'), 'my_app');
      expect(packageNameFromPubspec("name: 'my_app'\n"), 'my_app');
    });

    test('strips a trailing comment', () {
      expect(packageNameFromPubspec('name: my_app # the app\n'), 'my_app');
    });

    test('ignores an indented name: key nested under another section', () {
      const yaml = 'executables:\n  name: not_the_package\nname: real_pkg\n';
      expect(packageNameFromPubspec(yaml), 'real_pkg');
    });

    test('returns null when no top-level name: is present', () {
      const yaml = 'description: demo\nversion: 1.0.0\n';
      expect(packageNameFromPubspec(yaml), isNull);
    });

    test('returns null for empty input', () {
      expect(packageNameFromPubspec(''), isNull);
    });
  });

  group('projectPackagesFromDir', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('leak_graph_io_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    Future<void> writePubspec(String path, String name) async {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString('name: $name\n');
    }

    test('root-only: returns just the root package name', () async {
      await writePubspec('${tmpDir.path}/pubspec.yaml', 'root_pkg');

      final packages = await projectPackagesFromDir(tmpDir.path);

      expect(packages, {'root_pkg'});
    });

    test('root+members: returns root plus every workspace member', () async {
      await writePubspec('${tmpDir.path}/pubspec.yaml', 'root_pkg');
      await writePubspec('${tmpDir.path}/packages/foo/pubspec.yaml', 'foo_pkg');
      await writePubspec('${tmpDir.path}/packages/bar/pubspec.yaml', 'bar_pkg');

      final packages = await projectPackagesFromDir(tmpDir.path);

      expect(packages, {'root_pkg', 'foo_pkg', 'bar_pkg'});
    });

    test('missing root directory returns an empty set', () async {
      final missingDir = '${tmpDir.path}/does_not_exist';

      final packages = await projectPackagesFromDir(missingDir);

      expect(packages, isEmpty);
    });

    test(
      'root pubspec missing but members present: skips the root only',
      () async {
        await writePubspec(
          '${tmpDir.path}/packages/foo/pubspec.yaml',
          'foo_pkg',
        );

        final packages = await projectPackagesFromDir(tmpDir.path);

        expect(packages, {'foo_pkg'});
      },
    );

    test('a member pubspec with no name: is skipped, not thrown', () async {
      final badPubspec = File('${tmpDir.path}/packages/broken/pubspec.yaml');
      await badPubspec.parent.create(recursive: true);
      await badPubspec.writeAsString('description: no name here\n');
      await writePubspec('${tmpDir.path}/pubspec.yaml', 'root_pkg');

      final packages = await projectPackagesFromDir(tmpDir.path);

      expect(packages, {'root_pkg'});
    });

    test(
      'an unreadable packages/ dir degrades to the root name, never throws',
      () async {
        // Directory.exists() is true (stat succeeds) but .list() throws
        // PathAccessException — the scenario the plain-file trick can't
        // reach, since exists() would already be false and skip .list().
        // POSIX-only (matches this repo's macOS/ubuntu-latest toolchain).
        await writePubspec('${tmpDir.path}/pubspec.yaml', 'root_pkg');
        final membersDir = Directory('${tmpDir.path}/packages');
        await membersDir.create();
        Process.runSync('chmod', ['000', membersDir.path]);

        try {
          final packages = await projectPackagesFromDir(tmpDir.path);
          expect(packages, {'root_pkg'});
        } finally {
          // Restore permissions so tearDown's recursive delete can recurse
          // into (and remove) this directory.
          Process.runSync('chmod', ['755', membersDir.path]);
        }
      },
    );
  });
}
