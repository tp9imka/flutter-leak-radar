import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';

/// ```
/// dart run radar_native_host:radar_capture --package com.example.app \
///   --out capture.pftrace [--device SERIAL] [--mode attach|startup] \
///   [--duration 30s] [--sampling-interval 4096] [--tp-bin trace_processor]
/// ```
///
/// See [runCapture] for the preflight → capture → validate pipeline this thin
/// entry point delegates to.
Future<void> main(List<String> args) async => exit(await runCapture(args));
