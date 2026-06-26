// test/engine/vm_service_status_test.dart
import 'package:flutter_leak_radar/src/engine/vm_service_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VmServiceStatus', () {
    test('VmConnected is connected', () {
      const s = VmConnected();
      expect(s, isA<VmConnected>());
    });
    test('VmNoServiceUri is not connected', () {
      const s = VmNoServiceUri();
      expect(s is VmConnected, isFalse);
    });
    test('VmSocketError carries message', () {
      const s = VmSocketError(message: 'refused');
      expect(s.message, 'refused');
    });
    test('VmDisabled is not connected', () {
      const s = VmDisabled();
      expect(s is VmConnected, isFalse);
    });
    test('VmUnknown with null message', () {
      const s = VmUnknown();
      expect(s.message, isNull);
    });
    test('switch is exhaustive — all subtypes handled', () {
      final VmServiceStatus status = const VmNoServiceUri();
      final result = switch (status) {
        VmConnected() => 'connected',
        VmNoServiceUri() => 'no-uri',
        VmSocketError() => 'socket',
        VmDisabled() => 'disabled',
        VmUnknown() => 'unknown',
      };
      expect(result, 'no-uri');
    });
  });
}
