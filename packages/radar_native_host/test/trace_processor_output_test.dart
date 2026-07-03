import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

/// Projects the fields of [row] into a structurally-comparable record, so
/// two [PerfettoRow]s (which have no `==` override) can be compared via
/// [expect] without repeating field-by-field assertions.
(int, int, String, String, String?, int, int, int, int) _rowTuple(
  PerfettoRow row,
) => (
  row.callsiteId,
  row.depth,
  row.function,
  row.module,
  row.buildId,
  row.allocBytes,
  row.allocCount,
  row.freeBytes,
  row.freeCount,
);

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

  test('CRLF-terminated output parses identically to LF-terminated', () {
    const us = '\u001F';
    final row1 =
        '"7${us}0${us}malloc${us}libc.so$us${us}1024${us}2${us}0${us}0"';
    final row2 =
        '"7${us}1${us}Foo::bar${us}libflutter.so${us}abc${us}1024${us}2'
        '${us}0${us}0"';
    final lf = '"row"\n$row1\n$row2\n';
    final crlf = '"row"\r\n$row1\r\n$row2\r\n';

    final lfRows = parseTraceProcessorOutput(lf);
    final crlfRows = parseTraceProcessorOutput(crlf);

    expect(crlfRows, hasLength(2));
    expect(crlfRows.map(_rowTuple).toList(), lfRows.map(_rowTuple).toList());
  });

  test('skips a structurally malformed line without throwing', () {
    const us = '\u001F';
    final good1 =
        '"7${us}0${us}malloc${us}libc.so$us${us}1024${us}2${us}0${us}0"';
    final good2 =
        '"7${us}1${us}Foo::bar${us}libflutter.so${us}abc${us}1024${us}2'
        '${us}0${us}0"';
    // Wrong cell count: only 3 US-separated cells instead of 9. This is
    // structurally malformed and must be skipped, not thrown on, while
    // the surrounding valid rows still parse.
    final malformed = '"7${us}0${us}onlyThreeCells"';
    final out = '"row"\n$good1\n$malformed\n$good2\n';

    final rows = parseTraceProcessorOutput(out);

    expect(rows, hasLength(2));
    expect(rows[0].function, 'malloc');
    expect(rows[1].function, 'Foo::bar');
  });
}
