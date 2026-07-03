import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/screens/android_capture_form.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';

const _ready = AndroidDevice(
  serial: 'READY',
  state: 'device',
  model: 'KATIM X4',
  androidRelease: '15',
);
const _unauthorized = AndroidDevice(serial: 'UNAUTH', state: 'unauthorized');
const _offline = AndroidDevice(serial: 'OFFLINE', state: 'offline');

/// Pumps [AndroidCaptureForm] directly — this widget is purely
/// presentational, so its ready/unready filtering (Fix 4) can be exercised
/// without a controller or screen in the loop.
Future<void> _pumpForm(
  WidgetTester tester, {
  required List<AndroidDevice> devices,
  String? selectedSerial,
  VoidCallback? onCapture,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: radarDarkTheme(),
      home: Scaffold(
        body: AndroidCaptureForm(
          devices: devices,
          selectedSerial: selectedSerial,
          probing: false,
          capturing: false,
          mode: CaptureMode.startup,
          durationMs: 30000,
          justCaptured: false,
          onSelectDevice: (_) {},
          onRefreshDevices: () {},
          onPackageChanged: (_) {},
          onModeChanged: (_) {},
          onDurationChanged: (_) {},
          onCapture: onCapture,
        ),
      ),
    ),
  );
}

void main() {
  group('device readiness (Fix 4)', () {
    testWidgets(
      'a ready + an unauthorized device: dropdown lists only the ready '
      "device, and a 'not ready' caption reports the rest",
      (tester) async {
        await _pumpForm(
          tester,
          devices: const [_unauthorized, _ready],
          selectedSerial: _ready.serial,
        );

        final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        );
        expect(dropdown.items!.map((item) => item.value).toList(), [
          _ready.serial,
        ]);
        expect(find.text(_unauthorized.label), findsNothing);
        expect(
          find.text('1 other device(s) not ready (unauthorized/offline)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'only an unauthorized device: no dropdown, an honest unauthorized '
      'caption instead',
      (tester) async {
        await _pumpForm(tester, devices: const [_unauthorized]);

        expect(find.byType(DropdownButton<String>), findsNothing);
        expect(
          find.textContaining('Device unauthorized — accept'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'only an offline device: no dropdown, an honest offline caption',
      (tester) async {
        await _pumpForm(tester, devices: const [_offline]);

        expect(find.byType(DropdownButton<String>), findsNothing);
        expect(
          find.textContaining('Device offline — reconnect it'),
          findsOneWidget,
        );
      },
    );

    testWidgets('no ready device shows the disabled-capture hint above/below '
        'Capture', (tester) async {
      await _pumpForm(tester, devices: const [_unauthorized]);

      expect(
        find.text('Connect an authorized device to capture'),
        findsOneWidget,
      );
    });

    testWidgets(
      'no device at all: keeps the original empty-state caption, and the '
      'disabled-capture hint still applies (no ready device)',
      (tester) async {
        await _pumpForm(tester, devices: const []);

        expect(
          find.text('No device detected — connect one & enable USB debugging'),
          findsOneWidget,
        );
        expect(
          find.text('Connect an authorized device to capture'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a ready device with capture enabled shows no disabled-capture '
        'hint', (tester) async {
      await _pumpForm(
        tester,
        devices: const [_ready],
        selectedSerial: _ready.serial,
        onCapture: () {},
      );

      expect(
        find.text('Connect an authorized device to capture'),
        findsNothing,
      );
    });
  });
}
