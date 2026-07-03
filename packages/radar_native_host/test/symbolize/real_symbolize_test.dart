import 'dart:io';

import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

/// Exercises the real `llvm-readelf` + `llvm-symbolizer` tool wiring behind
/// [SymbolStoreBuilder], proving the seams work end to end against an actual
/// unstripped `.so`.
///
/// Skips (prints + returns) unless `RADAR_LLVM_SYMBOLIZER` and
/// `RADAR_SYMBOL_SO` are set. `RADAR_READELF` (default `llvm-readelf`) and
/// `RADAR_SYMBOL_ADDR` (a hex relative-PC known to resolve, default `0x0`)
/// are optional.
void main() {
  test(
    'SymbolStoreBuilder resolves a real address via real llvm tools',
    () async {
      final symbolizerBin = Platform.environment['RADAR_LLVM_SYMBOLIZER'];
      final soPath = Platform.environment['RADAR_SYMBOL_SO'];
      if (symbolizerBin == null || soPath == null) {
        print(
          '[skip] set RADAR_LLVM_SYMBOLIZER and RADAR_SYMBOL_SO (+ optional '
          'RADAR_READELF, RADAR_SYMBOL_ADDR) to run this test',
        );
        return;
      }

      final readelfBin = resolveReadelfBinary(env: Platform.environment);
      final addressHex = Platform.environment['RADAR_SYMBOL_ADDR'] ?? '0x0';
      final hexDigits = addressHex.startsWith('0x')
          ? addressHex.substring(2)
          : addressHex;
      final address = int.parse(hexDigits, radix: 16);
      // Canonical `0x<hex>` form, matching what the mapper/builder produce.
      final function = '0x${address.toRadixString(16)}';

      final buildIdReader = LlvmReadelfBuildIdReader(binaryPath: readelfBin);
      final buildId = await buildIdReader.readBuildId(soPath);
      expect(buildId, isNotNull, reason: '$soPath has no GNU build-id');

      final profile = NativeHeapProfile(
        capturedAt: DateTime.now(),
        label: 'real',
        meta: const NativeProfileMeta(),
        callsites: [
          NativeCallsite(
            frames: [
              NativeFrame(function: function, module: soPath, buildId: buildId),
            ],
            allocBytes: 1,
            allocCount: 1,
            freeBytes: 0,
            freeCount: 0,
          ),
        ],
      );

      final builder = SymbolStoreBuilder(
        buildIdReader: buildIdReader,
        symbolizer: LlvmSymbolizer(binaryPath: symbolizerBin),
      );
      final report = await builder.buildWithReport(profile, soPaths: [soPath]);

      expect(report.matchedBuildIds, 1);
      expect(
        report.resolvedAddresses,
        1,
        reason: 'address $addressHex did not resolve in $soPath',
      );

      final resolved = applySymbolStore(profile, report.store);
      final name = resolved.callsites.single.frames.single.function;
      expect(name, isNotEmpty);
      expect(name.startsWith('0x'), isFalse);
      print('[ok] $soPath build-id=$buildId $function -> $name');
    },
  );
}
