// test/engine/noop_heap_probe_test.dart
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NoopHeapProbe is unavailable and yields an empty snapshot', () async {
    const probe = NoopHeapProbe();
    expect(await probe.isAvailable, false);
    final snap = await probe.capture(forceGc: true);
    expect(snap.samples, isEmpty);
    expect(await probe.retainingPath('Anything'), isNull);
    await probe.dispose();
  });
}
