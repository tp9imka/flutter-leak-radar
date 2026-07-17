import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';

/// ```
/// dart run radar_native_host:radar_sample --package com.example.app \
///   [--device SERIAL] [--interval 5s] [--duration 8h] \
///   --out session_dir/ [--flush-every 60s]
/// ```
///
/// See [runSample] for the overnight-robust sampling loop this thin entry point
/// delegates to.
Future<void> main(List<String> args) async => exit(await runSample(args));
