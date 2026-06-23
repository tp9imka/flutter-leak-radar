// test/triggers/navigator_observer_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/triggers/navigator_observer.dart';

/// Minimal concrete Route implementation for use in tests.
/// [Route] is abstract; Flutter does not expose a public fake.
class _FakeRoute extends Route<void> {
  _FakeRoute() : super(settings: const RouteSettings());
}

void main() {
  group('LeakRadarNavigatorObserver', () {
    const debounce = Duration(milliseconds: 50);

    testWidgets(
      'single didPop triggers exactly one scan after debounce',
      (tester) async {
        var scanCount = 0;
        final observer = LeakRadarNavigatorObserver(
          onScan: () async => scanCount++,
          debounce: debounce,
        );

        observer.didPop(_FakeRoute(), _FakeRoute());

        // Before debounce expires — no scan yet.
        await tester.pump(const Duration(milliseconds: 20));
        expect(scanCount, 0);

        // After debounce expires — exactly one scan.
        await tester.pump(const Duration(milliseconds: 60));
        expect(scanCount, 1);

        observer.dispose();
      },
    );

    testWidgets(
      'rapid didPop calls are coalesced into a single scan',
      (tester) async {
        var scanCount = 0;
        final observer = LeakRadarNavigatorObserver(
          onScan: () async => scanCount++,
          debounce: debounce,
        );

        // Three pops within 20 ms each — all within one debounce window.
        observer.didPop(_FakeRoute(), _FakeRoute());
        await tester.pump(const Duration(milliseconds: 20));
        observer.didPop(_FakeRoute(), _FakeRoute());
        await tester.pump(const Duration(milliseconds: 20));
        observer.didPop(_FakeRoute(), _FakeRoute());

        // Let the debounce fire.
        await tester.pump(const Duration(milliseconds: 100));
        expect(scanCount, 1);

        observer.dispose();
      },
    );

    testWidgets(
      'didPush and didReplace do not trigger a scan',
      (tester) async {
        var scanCount = 0;
        final observer = LeakRadarNavigatorObserver(
          onScan: () async => scanCount++,
          debounce: debounce,
        );

        observer.didPush(_FakeRoute(), _FakeRoute());
        observer.didReplace(
          newRoute: _FakeRoute(),
          oldRoute: _FakeRoute(),
        );

        await tester.pump(const Duration(milliseconds: 60));
        expect(scanCount, 0);

        observer.dispose();
      },
    );

    testWidgets(
      'dispose cancels pending timer — no scan fires after dispose',
      (tester) async {
        var scanCount = 0;
        final observer = LeakRadarNavigatorObserver(
          onScan: () async => scanCount++,
          debounce: debounce,
        );

        observer.didPop(_FakeRoute(), _FakeRoute());

        // Dispose before the debounce window closes.
        observer.dispose();

        // Pump well past the debounce window.
        await tester.pump(const Duration(milliseconds: 200));
        expect(scanCount, 0);
      },
    );
  });
}
