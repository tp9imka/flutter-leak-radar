/// Builds the device-proven `heapprofd` Perfetto textproto config used to
/// drive an on-device capture session via `adb shell perfetto -c - --txt`.
///
/// All parameters are plain ASCII; the result contains no control
/// characters, so it can be piped to `adb` stdin as-is.
String heapprofdConfig({
  required String packageId,
  int samplingIntervalBytes = 4096,
  required int durationMs,
  int dumpIntervalMs = 3000,
  int bufferSizeKb = 131072,
  int shmemSizeBytes = 16777216,
}) =>
    'buffers { size_kb: $bufferSizeKb fill_policy: DISCARD }\n'
    'data_sources { config {\n'
    '  name: "android.heapprofd"\n'
    '  heapprofd_config {\n'
    '    sampling_interval_bytes: $samplingIntervalBytes\n'
    '    process_cmdline: "$packageId"\n'
    '    shmem_size_bytes: $shmemSizeBytes\n'
    '    block_client: true\n'
    '    continuous_dump_config { '
    'dump_phase_ms: 1000 dump_interval_ms: $dumpIntervalMs }\n'
    '  }\n'
    '} }\n'
    'duration_ms: $durationMs\n';
