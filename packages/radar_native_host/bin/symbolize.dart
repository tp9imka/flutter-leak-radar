import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';

/// ```
/// dart run radar_native_host:symbolize --trace capture.pftrace \
///   --so libA.so [--so libB.so ...] [--so-dir dir] --out symbols.json \
///   [--tp-bin trace_processor] [--symbolizer llvm-symbolizer] \
///   [--readelf llvm-readelf]
/// ```
///
/// See [runSymbolize] for the orchestration this thin entry point delegates
/// to.
Future<void> main(List<String> args) async => exit(await runSymbolize(args));
