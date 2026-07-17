import 'package:leak_graph/src/cli/cli_args.dart';
import 'package:test/test.dart';

void main() {
  group('parseCliArgs', () {
    test('parses dump path, repeated --package, flags, defaults', () {
      final c = parseCliArgs([
        'dump.data',
        '--package',
        'a',
        '--package',
        'b',
        '--all',
        '--min-cluster',
        '3',
      ]);
      expect(c.dumpPath, 'dump.data');
      expect(c.appPackages, ['a', 'b']);
      expect(c.all, isTrue);
      expect(c.minCluster, 3);
      expect(c.top, 50); // default
    });

    test('throws FormatException when dump path is missing', () {
      expect(() => parseCliArgs(['--all']), throwsFormatException);
    });

    test('all defaults to false', () {
      final c = parseCliArgs(['dump.data']);
      expect(c.all, isFalse);
    });

    test('appPackages defaults to empty list', () {
      final c = parseCliArgs(['dump.data']);
      expect(c.appPackages, isEmpty);
    });

    test('min-cluster defaults to 2', () {
      final c = parseCliArgs(['dump.data']);
      expect(c.minCluster, 2);
    });

    test('top can be overridden', () {
      final c = parseCliArgs(['dump.data', '--top', '10']);
      expect(c.top, 10);
    });

    test('--json sets jsonOut path', () {
      final c = parseCliArgs(['dump.data', '--json', 'out.json']);
      expect(c.jsonOut, 'out.json');
    });

    test('jsonOut is null when --json not passed', () {
      final c = parseCliArgs(['dump.data']);
      expect(c.jsonOut, isNull);
    });

    test('--confirm parses to true', () {
      final c = parseCliArgs(['dump.data', '--confirm']);
      expect(c.confirm, isTrue);
    });

    test('confirm defaults to false', () {
      final c = parseCliArgs(['dump.data']);
      expect(c.confirm, isFalse);
    });

    test('format defaults to text', () {
      final c = parseCliArgs(['dump.data']);
      expect(c.format, CliOutputFormat.text);
    });

    test('--format accepts text, json, md, github', () {
      expect(
        parseCliArgs(['dump.data', '--format', 'text']).format,
        CliOutputFormat.text,
      );
      expect(
        parseCliArgs(['dump.data', '--format', 'json']).format,
        CliOutputFormat.json,
      );
      expect(
        parseCliArgs(['dump.data', '--format', 'md']).format,
        CliOutputFormat.markdown,
      );
      expect(
        parseCliArgs(['dump.data', '--format', 'github']).format,
        CliOutputFormat.github,
      );
    });

    test('--format rejects an unknown value', () {
      expect(
        () => parseCliArgs(['dump.data', '--format', 'yaml']),
        throwsFormatException,
      );
    });
  });
}
