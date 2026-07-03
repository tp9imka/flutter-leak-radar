import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/android/perfetto_trace_importer.dart';

void main() {
  group('resolveTraceProcessorBinary', () {
    test('explicit wins over env', () {
      expect(
        resolveTraceProcessorBinary(
          explicit: '/opt/explicit/trace_processor_shell',
          env: const {'RADAR_TP_BIN': '/opt/env/trace_processor_shell'},
        ),
        '/opt/explicit/trace_processor_shell',
      );
    });

    test('falls back to RADAR_TP_BIN when no explicit path', () {
      expect(
        resolveTraceProcessorBinary(
          env: const {'RADAR_TP_BIN': '/opt/env/trace_processor_shell'},
        ),
        '/opt/env/trace_processor_shell',
      );
    });

    test('ignores a null or empty explicit path and falls back to env', () {
      expect(
        resolveTraceProcessorBinary(
          explicit: '',
          env: const {'RADAR_TP_BIN': '/opt/env/trace_processor_shell'},
        ),
        '/opt/env/trace_processor_shell',
      );
    });

    test('throws StateError naming both options when neither is set', () {
      expect(
        () => resolveTraceProcessorBinary(env: const {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('RADAR_TP_BIN'), contains('trace_processor')),
          ),
        ),
      );
    });

    test('treats an empty RADAR_TP_BIN as unset', () {
      expect(
        () => resolveTraceProcessorBinary(env: const {'RADAR_TP_BIN': ''}),
        throwsStateError,
      );
    });
  });
}
