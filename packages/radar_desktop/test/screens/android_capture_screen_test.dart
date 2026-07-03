import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_capture_screen.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';

/// No file-pick platform-channel calls are driven by these tests (matching
/// `dumps_screen.dart`'s untested `_browse` pattern) — this fake is never
/// actually invoked unless a captured trace needs parsing.
class _FakeImporter implements NativeTraceImporter {
  _FakeImporter({Map<String, NativeHeapProfile> profilesByLabel = const {}})
    : _profilesByLabel = profilesByLabel;

  final Map<String, NativeHeapProfile> _profilesByLabel;

  @override
  Future<NativeHeapProfile> importTrace(
    String path, {
    required String label,
  }) async {
    final profile = _profilesByLabel[label];
    if (profile == null) {
      throw StateError('_FakeImporter has no canned profile for "$label"');
    }
    return profile;
  }

  @override
  Future<SymbolStore> importSymbolStore(String path) async =>
      throw UnimplementedError('not needed by these tests');

  @override
  Future<FfiAllocationLog> importFfiLog(String path) async =>
      throw UnimplementedError('not needed by these tests');
}

/// Fixed one-device probe result, matching the pattern used in
/// `test/android/native_profiling_controller_test.dart`.
class _FakeDeviceProbe implements DeviceProbe {
  const _FakeDeviceProbe();

  static const device = AndroidDevice(
    serial: 'DEV',
    state: 'device',
    model: 'KATIM X3M',
    androidRelease: '15',
  );

  @override
  Future<List<AndroidDevice>> probe() async => const [device];
}

/// Stands in for a real `adb`-driven capture: writes dummy bytes to
/// `outputPath` and records the last request so tests can assert the
/// screen forwarded the right values, without ever shelling out to `adb`.
class _FakeCapture implements NativeHeapCapture {
  CaptureRequest? lastRequest;

  @override
  Future<String> capture(
    CaptureRequest request, {
    required String outputPath,
  }) async {
    lastRequest = request;
    File(outputPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(4096, 0));
    return outputPath;
  }
}

NativeHeapProfile _profile(String label) => NativeHeapProfile(
  capturedAt: DateTime(2026, 1, 1),
  label: label,
  meta: const NativeProfileMeta(),
  callsites: const [
    NativeCallsite(
      frames: [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
      ],
      allocBytes: 1000,
      allocCount: 10,
      freeBytes: 200,
      freeCount: 2,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  NativeProfilingController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(body: AndroidCaptureScreen(controller: controller)),
    ),
  );
  // Flush the post-frame `refreshDevices()` call so a real device-capture
  // scenario finishes probing before assertions run.
  await tester.pump();
}

/// The [FilledButton] labeled [label]. `FilledButton.icon` returns the
/// private subtype `_FilledButtonWithIcon`, which `find.byType` (an exact
/// runtimeType match) never finds — `bySubtype` matches it correctly.
Finder _buttonLabeled(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<FilledButton>(),
);

void main() {
  testWidgets('renders the three enabled import actions', (tester) async {
    await _pump(tester, NativeProfilingController(_FakeImporter()));

    for (final label in [
      'Import Perfetto trace',
      'Attach symbol store',
      'Import ffi log',
    ]) {
      final button = tester.widget<FilledButton>(_buttonLabeled(label));
      expect(button.onPressed, isNotNull, reason: '$label should be enabled');
    }
  });

  testWidgets('states the prerequisites plainly', (tester) async {
    await _pump(tester, NativeProfilingController(_FakeImporter()));

    expect(find.textContaining('Android only'), findsOneWidget);
    expect(find.textContaining('iOS not supported'), findsOneWidget);
    expect(
      find.textContaining('profile the profile/release build'),
      findsOneWidget,
    );
    expect(find.textContaining('RADAR_TP_BIN'), findsOneWidget);
  });

  group('without capture seams', () {
    testWidgets('shows the connect-a-device hint, not a capture form', (
      tester,
    ) async {
      await _pump(tester, NativeProfilingController(_FakeImporter()));

      expect(
        find.textContaining('Connect a device & enable USB debugging'),
        findsOneWidget,
      );
      expect(_buttonLabeled('Capture'), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
    });
  });

  group('with capture seams', () {
    testWidgets('a seeded device renders enabled with its label shown', (
      tester,
    ) async {
      final controller = NativeProfilingController(
        _FakeImporter(),
        deviceProbe: const _FakeDeviceProbe(),
        capture: _FakeCapture(),
      );

      await _pump(tester, controller);

      expect(find.text(_FakeDeviceProbe.device.label), findsOneWidget);
      final captureButton = tester.widget<FilledButton>(
        _buttonLabeled('Capture'),
      );
      // Disabled until a package id is entered.
      expect(captureButton.onPressed, isNull);
    });

    testWidgets(
      'entering a package and tapping Capture invokes captureAndImport '
      'with the entered package, mode, and selected device',
      (tester) async {
        final capture = _FakeCapture();
        final controller = NativeProfilingController(
          _FakeImporter(profilesByLabel: {'com.katim.leak_lab': _profile('c')}),
          deviceProbe: const _FakeDeviceProbe(),
          capture: capture,
        );

        await _pump(tester, controller);

        await tester.enterText(find.byType(TextField), 'com.katim.leak_lab');
        await tester.pump();

        final captureButton = tester.widget<FilledButton>(
          _buttonLabeled('Capture'),
        );
        expect(captureButton.onPressed, isNotNull);

        await tester.tap(_buttonLabeled('Capture'));
        await tester.pump();
        await tester.pump();

        expect(capture.lastRequest?.packageId, 'com.katim.leak_lab');
        // Startup is the screen's default mode.
        expect(capture.lastRequest?.mode, CaptureMode.startup);
        expect(capture.lastRequest?.serial, 'DEV');
        expect(find.textContaining('Captured & imported'), findsOneWidget);
      },
    );

    testWidgets('no device detected shows the connect hint inline', (
      tester,
    ) async {
      final controller = NativeProfilingController(
        _FakeImporter(),
        deviceProbe: _EmptyDeviceProbe(),
        capture: _FakeCapture(),
      );

      await _pump(tester, controller);

      expect(find.textContaining('No device detected'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
    });
  });
}

/// A [DeviceProbe] that always finds nothing, for the "no device plugged
/// in yet" capture-form state.
class _EmptyDeviceProbe implements DeviceProbe {
  @override
  Future<List<AndroidDevice>> probe() async => const [];
}
