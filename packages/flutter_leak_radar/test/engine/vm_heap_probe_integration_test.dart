// test/engine/vm_heap_probe_integration_test.dart
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VmHeapProbe captures a non-empty profile when the service is present',
      () async {
    final probe = VmHeapProbe();
    if (!await probe.isAvailable) {
      // No VM service in this runner; nothing to assert.
      return;
    }
    // Retain instances so they appear in the profile.
    // ignore: unused_local_variable
    final retained = List.generate(1000, (i) => _Marker());
    final snap = await probe.capture(forceGc: true);
    expect(snap.samples, isNotEmpty);
    expect(snap.samples.any((s) => s.className == '_Marker'), isTrue);
    await probe.dispose();
  });
}

class _Marker {}
