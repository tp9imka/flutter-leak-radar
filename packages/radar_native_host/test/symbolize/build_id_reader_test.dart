import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

const _readelfOutputWithBuildId =
    "Displaying notes found in: .note.android.ident\n"
    "  Owner                Data size \tDescription\n"
    "  Android              0x00000014\tNT_VERSION (version)\n"
    "Displaying notes found in: .note.gnu.build-id\n"
    "  Owner                Data size \tDescription\n"
    "  GNU                  0x00000014\tNT_GNU_BUILD_ID (unique build ID "
    "bitstring)\n"
    "    Build ID: 1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c\n";

const _readelfOutputWithoutBuildId =
    "Displaying notes found in: .note.android.ident\n"
    "  Owner                Data size \tDescription\n"
    "  Android              0x00000014\tNT_VERSION (version)\n";

void main() {
  group('parseBuildId', () {
    test('extracts the hex build-id from a readelf -n notes block', () {
      final buildId = parseBuildId(_readelfOutputWithBuildId);

      expect(buildId, '1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c');
    });

    test('returns null when no build-id note is present', () {
      expect(parseBuildId(_readelfOutputWithoutBuildId), isNull);
    });

    test('returns null for empty stdout', () {
      expect(parseBuildId(''), isNull);
    });

    test('matches the label case-insensitively', () {
      final buildId = parseBuildId('    build id: DEADBEEF01234567\n');

      expect(buildId, 'deadbeef01234567');
    });

    test('strips embedded whitespace from the hex value', () {
      final buildId = parseBuildId('    Build ID: 1b2c 3d4e 5f6a\n');

      expect(buildId, '1b2c3d4e5f6a');
    });
  });

  group('resolveReadelfBinary', () {
    test('prefers the explicit path over everything else', () {
      final binary = resolveReadelfBinary(
        explicit: '/opt/llvm/bin/llvm-readelf',
        env: {'RADAR_READELF': '/usr/bin/readelf'},
      );

      expect(binary, '/opt/llvm/bin/llvm-readelf');
    });

    test('falls back to RADAR_READELF when no explicit path is given', () {
      final binary = resolveReadelfBinary(
        env: {'RADAR_READELF': '/usr/bin/readelf'},
      );

      expect(binary, '/usr/bin/readelf');
    });

    test('falls back to the bare llvm-readelf name by default', () {
      expect(resolveReadelfBinary(env: {}), 'llvm-readelf');
    });

    test('ignores a null environment map', () {
      expect(resolveReadelfBinary(), 'llvm-readelf');
    });
  });

  group('LlvmReadelfBuildIdReader', () {
    test('exposes the configured binary path', () {
      const reader = LlvmReadelfBuildIdReader(binaryPath: '/bin/readelf');

      expect(reader.binaryPath, '/bin/readelf');
    });

    test('defaults to the bare llvm-readelf name', () {
      const reader = LlvmReadelfBuildIdReader();

      expect(reader.binaryPath, 'llvm-readelf');
    });
  });

  group('SymbolizeToolException', () {
    test('toString includes the message and stderr', () {
      const exception = SymbolizeToolException(
        'llvm-readelf exited with code 1',
        stderr: 'no such file',
      );

      expect(exception.toString(), contains('llvm-readelf exited'));
      expect(exception.toString(), contains('no such file'));
    });
  });
}
