import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeAllocationDiff d(int before, int after) => NativeAllocationDiff(
  signature: 's',
  frames: const [],
  beforeStillLiveBytes: before,
  afterStillLiveBytes: after,
  beforeStillLiveCount: before == 0 ? 0 : 1,
  afterStillLiveCount: after == 0 ? 0 : 1,
);

void main() {
  test('status classifies added/gone/grew/shrank/flat', () {
    expect(d(0, 100).status, NativeDiffStatus.added);
    expect(d(100, 0).status, NativeDiffStatus.gone);
    expect(d(100, 300).status, NativeDiffStatus.grew);
    expect(d(300, 100).status, NativeDiffStatus.shrank);
    expect(d(200, 200).status, NativeDiffStatus.flat);
  });
}
