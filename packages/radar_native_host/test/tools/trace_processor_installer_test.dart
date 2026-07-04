import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

void main() {
  group('TraceProcessorInstaller.install', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'trace_processor_installer_test_',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('creates parent dirs, downloads to destPath, chmods it executable, '
        'and returns destPath', () async {
      final destPath = '${tempDir.path}/nested/bin/trace_processor';
      String? calledUrl;
      String? calledDest;
      final installer = TraceProcessorInstaller(
        download: (url, dest) async {
          calledUrl = url;
          calledDest = dest;
          await File(dest).writeAsString('stub trace_processor binary');
        },
      );

      final result = await installer.install(destPath: destPath);

      expect(result, destPath);
      expect(calledUrl, TraceProcessorInstaller.url);
      expect(calledDest, destPath);
      expect(Directory('${tempDir.path}/nested/bin').existsSync(), isTrue);
      expect(File(destPath).existsSync(), isTrue);
      expect(File(destPath).statSync().modeString(), contains('x'));
    });

    test(
      'a download that throws propagates the error and leaves no dest file',
      () async {
        final destPath = '${tempDir.path}/bin/trace_processor';
        final installer = TraceProcessorInstaller(
          download: (url, dest) async => throw Exception('network down'),
        );

        await expectLater(
          () => installer.install(destPath: destPath),
          throwsA(isA<Exception>()),
        );
        expect(File(destPath).existsSync(), isFalse);
      },
    );

    test('a download that reports success but writes no file surfaces a '
        'clear TraceProcessorInstallException from the failed chmod', () async {
      final destPath = '${tempDir.path}/bin/trace_processor';
      final installer = TraceProcessorInstaller(download: (url, dest) async {});

      await expectLater(
        () => installer.install(destPath: destPath),
        throwsA(isA<TraceProcessorInstallException>()),
      );
    });
  });
}
