import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

void main() {
  test('parses quoted single-column US-delimited output, skips header', () {
    const us = '\u001F';
    final out =
        '"row"\n'
        '"7${us}0${us}malloc${us}libc.so$us${us}1024${us}2${us}0${us}0"\n'
        '"7${us}1${us}Foo::bar${us}libflutter.so${us}abc${us}1024${us}2'
        '${us}0${us}0"\n';
    final rows = parseTraceProcessorOutput(out);
    expect(rows, hasLength(2));
    expect(rows[0].callsiteId, 7);
    expect(rows[0].module, 'libc.so');
    expect(rows[0].buildId, isNull); // empty build_id field
    expect(rows[1].function, 'Foo::bar');
    expect(rows[1].buildId, 'abc');
  });

  test('handles CSV-escaped embedded quotes and ignores blank lines', () {
    const us = '\u001F';
    final out =
        '"row"\n\n'
        '"1${us}0${us}op""x""${us}libc.so$us${us}8${us}1${us}0${us}0"\n';
    final rows = parseTraceProcessorOutput(out);
    expect(rows, hasLength(1));
    expect(rows[0].function, 'op"x"'); // "" -> "
  });
}
