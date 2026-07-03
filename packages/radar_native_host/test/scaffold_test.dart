import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

void main() {
  test('radar_native resolves', () {
    expect(const NativeProfileMeta().pid, isNull);
  });
}
