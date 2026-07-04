import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/screens/android_capture_screen.dart';
import 'package:radar_desktop/src/tools/tools_controller.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';

/// In-memory [ToolConfigStore] fake — no real fs/path_provider.
class _FakeToolConfigStore implements ToolConfigStore {
  @override
  Future<ToolConfig> read() async => const ToolConfig({});

  @override
  Future<void> write(ToolConfig config) async {}
}

/// A [ToolProbe] whose bare-name (PATH-tier) candidate verifies only for
/// tool ids in [workingIds] — never touches the real filesystem or
/// spawns a process.
ToolProbe _fakeProbe(Set<String> workingIds) => ToolProbe(
  exists: workingIds.contains,
  run: (exe, args) async => workingIds.contains(exe)
      ? (exitCode: 0, stdout: '$exe v1', stderr: '')
      : (exitCode: 1, stdout: '', stderr: 'not found'),
  // Each tool id resolves as an existence-checked location (no bare-name spawn).
  commonLocations: (tool) => [tool.id],
);

/// A loaded [ToolsController] reporting every [ExternalTool] present
/// except those in [missing].
Future<ToolsController> _toolsWithMissing(Set<ExternalTool> missing) async {
  final present = {
    for (final tool in ExternalTool.values)
      if (!missing.contains(tool)) tool.id,
  };
  final controller = ToolsController(
    probe: _fakeProbe(present),
    store: _FakeToolConfigStore(),
  );
  await controller.load();
  return controller;
}

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

/// A ready device sorting *after* an unauthorized one, so resolution logic
/// (Fix 3) is actually exercised rather than trivially picking the first
/// entry.
class _MixedDeviceProbe implements DeviceProbe {
  const _MixedDeviceProbe();

  static const unauthorized = AndroidDevice(
    serial: 'UNAUTH',
    state: 'unauthorized',
  );
  static const ready = AndroidDevice(
    serial: 'READY',
    state: 'device',
    model: 'KATIM X4',
    androidRelease: '15',
  );

  @override
  Future<List<AndroidDevice>> probe() async => const [unauthorized, ready];
}

/// Only an unauthorized device — no ready device exists at all.
class _UnauthorizedOnlyDeviceProbe implements DeviceProbe {
  const _UnauthorizedOnlyDeviceProbe();

  @override
  Future<List<AndroidDevice>> probe() async => const [
    AndroidDevice(serial: 'UNAUTH', state: 'unauthorized'),
  ];
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
  NativeProfilingController controller, {
  ToolsController? tools,
  VoidCallback? onOpenTools,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(
        body: AndroidCaptureScreen(
          controller: controller,
          tools: tools,
          onOpenTools: onOpenTools,
        ),
      ),
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

/// [BuildIdReader]/[Symbolizer] stand-ins that are never actually invoked by
/// these visibility-only widget tests — real file-picker-driven flows
/// aren't exercised here either, matching `_FakeImporter`'s doc comment.
class _NoopBuildIdReader implements BuildIdReader {
  const _NoopBuildIdReader();

  @override
  Future<String?> readBuildId(String soPath) async =>
      throw UnimplementedError('not needed by these tests');
}

class _NoopSymbolizer implements Symbolizer {
  const _NoopSymbolizer();

  @override
  Future<String?> symbolize({
    required String soPath,
    required int address,
  }) async => throw UnimplementedError('not needed by these tests');
}

void main() {
  group('resolve from .so directory action', () {
    testWidgets('hidden with no SymbolStoreBuilder injected', (tester) async {
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': _profile('before')}),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      await _pump(tester, controller);

      expect(_buttonLabeled('Resolve from .so directory'), findsNothing);
    });

    testWidgets('hidden when a builder is injected but nothing is selected', (
      tester,
    ) async {
      await _pump(
        tester,
        NativeProfilingController(
          _FakeImporter(),
          symbolStoreBuilder: const SymbolStoreBuilder(
            buildIdReader: _NoopBuildIdReader(),
            symbolizer: _NoopSymbolizer(),
          ),
        ),
      );

      expect(_buttonLabeled('Resolve from .so directory'), findsNothing);
    });

    testWidgets('shown once a builder is injected and a checkpoint is '
        'selected', (tester) async {
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': _profile('before')}),
        symbolStoreBuilder: const SymbolStoreBuilder(
          buildIdReader: _NoopBuildIdReader(),
          symbolizer: _NoopSymbolizer(),
        ),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      await _pump(tester, controller);

      final button = tester.widget<FilledButton>(
        _buttonLabeled('Resolve from .so directory'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

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

  group('device readiness (Fix 3)', () {
    testWidgets(
      'resolves the ready device even when it does not sort first, and '
      'Capture enables once a package is entered',
      (tester) async {
        final controller = NativeProfilingController(
          _FakeImporter(),
          deviceProbe: const _MixedDeviceProbe(),
          capture: _FakeCapture(),
        );

        await _pump(tester, controller);

        final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        );
        expect(dropdown.value, _MixedDeviceProbe.ready.serial);

        await tester.enterText(find.byType(TextField), 'com.katim.leak_lab');
        await tester.pump();

        final captureButton = tester.widget<FilledButton>(
          _buttonLabeled('Capture'),
        );
        expect(captureButton.onPressed, isNotNull);
      },
    );

    testWidgets('Capture stays disabled with only an unauthorized device, even '
        'with a package entered', (tester) async {
      final controller = NativeProfilingController(
        _FakeImporter(),
        deviceProbe: const _UnauthorizedOnlyDeviceProbe(),
        capture: _FakeCapture(),
      );

      await _pump(tester, controller);

      await tester.enterText(find.byType(TextField), 'com.katim.leak_lab');
      await tester.pump();

      final captureButton = tester.widget<FilledButton>(
        _buttonLabeled('Capture'),
      );
      expect(captureButton.onPressed, isNull);
    });
  });

  group('missing-tool banners', () {
    testWidgets(
      'shows the missing trace_processor banner and its action opens Tools',
      (tester) async {
        final tools = await _toolsWithMissing({ExternalTool.traceProcessor});
        var opened = 0;
        await _pump(
          tester,
          NativeProfilingController(_FakeImporter()),
          tools: tools,
          onOpenTools: () => opened++,
        );

        expect(
          find.textContaining('trace_processor not found'),
          findsOneWidget,
        );

        await tester.tap(find.text('Open Tools'));
        expect(opened, 1);
      },
    );

    testWidgets('hides the banner when trace_processor is present', (
      tester,
    ) async {
      final tools = await _toolsWithMissing(const {});
      await _pump(
        tester,
        NativeProfilingController(_FakeImporter()),
        tools: tools,
      );

      expect(find.textContaining('trace_processor not found'), findsNothing);
    });

    testWidgets('hides the banner when tools is null', (tester) async {
      await _pump(tester, NativeProfilingController(_FakeImporter()));

      expect(find.textContaining('trace_processor not found'), findsNothing);
    });

    testWidgets(
      'hints missing llvm binaries near the Resolve from .so directory '
      'action',
      (tester) async {
        final tools = await _toolsWithMissing({ExternalTool.llvmSymbolizer});
        final controller = NativeProfilingController(
          _FakeImporter(profilesByLabel: {'before': _profile('before')}),
          symbolStoreBuilder: const SymbolStoreBuilder(
            buildIdReader: _NoopBuildIdReader(),
            symbolizer: _NoopSymbolizer(),
          ),
        );
        await controller.importTrace('before.pftrace', label: 'before');

        await _pump(tester, controller, tools: tools);

        expect(
          find.textContaining('llvm-symbolizer/llvm-readelf not found'),
          findsOneWidget,
        );
      },
    );

    testWidgets('no llvm hint when the Resolve action is not shown (no builder '
        'injected), even if llvm is missing', (tester) async {
      final tools = await _toolsWithMissing({ExternalTool.llvmSymbolizer});
      await _pump(
        tester,
        NativeProfilingController(_FakeImporter()),
        tools: tools,
      );

      expect(
        find.textContaining('llvm-symbolizer/llvm-readelf not found'),
        findsNothing,
      );
    });
  });
}

/// A [DeviceProbe] that always finds nothing, for the "no device plugged
/// in yet" capture-form state.
class _EmptyDeviceProbe implements DeviceProbe {
  @override
  Future<List<AndroidDevice>> probe() async => const [];
}
