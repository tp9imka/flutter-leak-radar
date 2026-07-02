import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

void main() {
  test('InMemoryNativeProfileParser.parse returns the wrapped profile', () {
    final profile = NativeHeapProfile(
      capturedAt: DateTime.utc(2026, 1, 1, 9),
      label: 'before',
      callsites: const [],
      meta: const NativeProfileMeta(pid: 123),
    );
    final NativeProfileParser parser = InMemoryNativeProfileParser(profile);

    final parsed = parser.parse(Object(), label: 'before');

    expect(parsed, same(profile));
  });
}
