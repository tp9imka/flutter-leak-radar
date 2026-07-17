import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/workspace/desktop_project_context.dart';
import 'package:radar_desktop/src/workspace/package_config_resolver.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('radar_pkg_config_test_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void writePackageConfig(List<Map<String, Object?>> packages) {
    final file = File('${root.path}/.dart_tool/package_config.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'configVersion': 2, 'packages': packages}),
    );
  }

  group('PackageConfigResolver', () {
    test('maps a package uri to an absolute path via the config', () async {
      writePackageConfig([
        {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
      ]);
      final resolver = PackageConfigResolver(root.path);

      final path = await resolver.resolve(
        Uri.parse('package:my_app/screen/home.dart'),
      );

      expect(path, '${root.path}/lib/screen/home.dart');
    });

    test('resolves a package rooted at an absolute file uri', () async {
      final pkgDir = Directory('${root.path}/external/foo')
        ..createSync(recursive: true);
      writePackageConfig([
        {
          'name': 'foo',
          'rootUri': Uri.directory(pkgDir.path).toString(),
          'packageUri': 'lib/',
        },
      ]);
      final resolver = PackageConfigResolver(root.path);

      final path = await resolver.resolve(Uri.parse('package:foo/bar.dart'));

      expect(path, '${pkgDir.path}/lib/bar.dart');
    });

    test('returns null for a package the config does not list', () async {
      writePackageConfig([
        {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
      ]);
      final resolver = PackageConfigResolver(root.path);

      expect(
        await resolver.resolve(Uri.parse('package:unknown/x.dart')),
        isNull,
      );
    });

    test('returns null (never throws) when the config is missing', () async {
      final resolver = PackageConfigResolver(root.path);
      expect(
        await resolver.resolve(Uri.parse('package:my_app/x.dart')),
        isNull,
      );
    });

    test('returns null (never throws) on malformed config json', () async {
      final file = File('${root.path}/.dart_tool/package_config.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{ not valid json');
      final resolver = PackageConfigResolver(root.path);

      expect(
        await resolver.resolve(Uri.parse('package:my_app/x.dart')),
        isNull,
      );
    });

    test('returns null for a non-package uri', () async {
      writePackageConfig([
        {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
      ]);
      final resolver = PackageConfigResolver(root.path);
      expect(await resolver.resolve(Uri.parse('dart:async')), isNull);
    });
  });

  group('DesktopProjectContext.openSource', () {
    test('launches the resolved path and reports success', () async {
      writePackageConfig([
        {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
      ]);
      String? launched;
      final ctx = DesktopProjectContext(
        projectRoot: root.path,
        launcher: (path) async {
          launched = path;
          return true;
        },
      );

      final opened = await ctx.openSource(
        Uri.parse('package:my_app/screen.dart'),
      );

      expect(opened, isTrue);
      expect(launched, '${root.path}/lib/screen.dart');
      expect(ctx.canOpenSource, isTrue);
    });

    test(
      'returns false without launching when the uri is unresolvable',
      () async {
        writePackageConfig([
          {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
        ]);
        var launched = false;
        final ctx = DesktopProjectContext(
          projectRoot: root.path,
          launcher: (path) async {
            launched = true;
            return true;
          },
        );

        final opened = await ctx.openSource(Uri.parse('package:other/x.dart'));

        expect(opened, isFalse);
        expect(launched, isFalse);
      },
    );

    test('is inert with no project root: no packages, cannot open', () async {
      final ctx = DesktopProjectContext();
      expect(await ctx.projectPackages(), isEmpty);
      expect(ctx.sourceLabel, 'none');
      expect(ctx.canOpenSource, isFalse);
      expect(await ctx.openSource(Uri.parse('package:my_app/x.dart')), isFalse);
    });

    test('detects project packages from the workspace pubspec', () async {
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: my_app\n');
      final ctx = DesktopProjectContext(projectRoot: root.path);

      expect(await ctx.projectPackages(), {'my_app'});
      expect(ctx.sourceLabel, 'workspace');
    });
  });
}
