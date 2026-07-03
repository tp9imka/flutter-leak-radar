import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

void main() {
  group('parseSymbolizerOutput', () {
    test('returns the function name from the first line', () {
      final name = parseSymbolizerOutput(
        'flutter::Shell::Run\n/p/shell.cc:12:3\n',
      );

      expect(name, 'flutter::Shell::Run');
    });

    test('returns null when the first line is ??', () {
      expect(parseSymbolizerOutput('??\n??:0:0\n'), isNull);
    });

    test('returns null for empty stdout', () {
      expect(parseSymbolizerOutput(''), isNull);
    });

    test('returns null for stdout with only blank lines', () {
      expect(parseSymbolizerOutput('\n\n'), isNull);
    });

    test('trims surrounding whitespace from the function name', () {
      final name = parseSymbolizerOutput(
        '  flutter::Shell::Run  \n/p/shell.cc:12:3\n',
      );

      expect(name, 'flutter::Shell::Run');
    });
  });

  group('resolveSymbolizerBinary', () {
    test('prefers the explicit path over everything else', () {
      final binary = resolveSymbolizerBinary(
        explicit: '/opt/llvm/bin/llvm-symbolizer',
        env: {'RADAR_LLVM_SYMBOLIZER': '/usr/bin/llvm-symbolizer'},
      );

      expect(binary, '/opt/llvm/bin/llvm-symbolizer');
    });

    test(
      'falls back to RADAR_LLVM_SYMBOLIZER when no explicit path is given',
      () {
        final binary = resolveSymbolizerBinary(
          env: {'RADAR_LLVM_SYMBOLIZER': '/usr/bin/llvm-symbolizer'},
        );

        expect(binary, '/usr/bin/llvm-symbolizer');
      },
    );

    test('falls back to the bare llvm-symbolizer name by default', () {
      expect(resolveSymbolizerBinary(env: {}), 'llvm-symbolizer');
    });

    test('ignores a null environment map', () {
      expect(resolveSymbolizerBinary(), 'llvm-symbolizer');
    });
  });

  group('LlvmSymbolizer', () {
    test('exposes the configured binary path', () {
      const symbolizer = LlvmSymbolizer(binaryPath: '/bin/llvm-symbolizer');

      expect(symbolizer.binaryPath, '/bin/llvm-symbolizer');
    });

    test('defaults to the bare llvm-symbolizer name', () {
      const symbolizer = LlvmSymbolizer();

      expect(symbolizer.binaryPath, 'llvm-symbolizer');
    });
  });
}
