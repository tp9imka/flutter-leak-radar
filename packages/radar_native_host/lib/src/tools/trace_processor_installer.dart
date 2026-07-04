import 'dart:io';

/// Downloads bytes from [url] to [destPath]. The real implementation
/// streams an `HttpClient` GET (following redirects) to a sibling temp
/// file, then renames it into place; tests inject a fake that writes a
/// stub file directly, so no real network access happens in unit tests.
typedef Downloader = Future<void> Function(String url, String destPath);

/// Fetches the single-file `trace_processor` binary from
/// `get.perfetto.dev`, makes it executable, and returns its final path.
///
/// `trace_processor` is the only external tool Radar Desktop can offer a
/// true one-click install for — it ships as a single self-contained
/// static binary with no package-manager step, unlike `adb`/`llvm-*`,
/// which stay discover-and-"Locate…" only (see the tool-management
/// plan's global constraints).
final class TraceProcessorInstaller {
  const TraceProcessorInstaller({Downloader? download})
    : _download = download ?? _defaultDownload;

  final Downloader _download;

  /// Perfetto's stable single-binary download endpoint; always resolves
  /// to the latest `trace_processor` build compatible with the current
  /// Perfetto trace format.
  static const String url = 'https://get.perfetto.dev/trace_processor';

  /// Downloads `trace_processor` to [destPath] — creating its parent
  /// directory first — then marks it executable (`chmod +x`). Returns
  /// [destPath] on success.
  ///
  /// Propagates a [_download] failure, or a
  /// [TraceProcessorInstallException] from a failed `chmod`, without
  /// leaving [destPath] behind: a well-behaved [Downloader] (including
  /// the default one) only creates [destPath] once the download has
  /// fully succeeded.
  Future<String> install({required String destPath}) async {
    await File(destPath).parent.create(recursive: true);
    await _download(url, destPath);

    final chmod = await Process.run('chmod', ['+x', destPath]);
    if (chmod.exitCode != 0) {
      throw TraceProcessorInstallException(
        'chmod +x failed on $destPath: ${chmod.stderr}',
      );
    }
    return destPath;
  }
}

/// Thrown when installing `trace_processor` fails: a non-200 download
/// response, or a failed `chmod +x` on the downloaded file.
final class TraceProcessorInstallException implements Exception {
  const TraceProcessorInstallException(this.message);

  final String message;

  @override
  String toString() => 'TraceProcessorInstallException: $message';
}

/// Real [Downloader]: streams an `HttpClient` GET of [url] (following
/// redirects) to a sibling `<destPath>.download` temp file, then renames
/// it into place at [destPath] — so a failed or interrupted download
/// never leaves a partial file where [destPath] is expected. Throws
/// [TraceProcessorInstallException] on any non-200 response.
Future<void> _defaultDownload(String url, String destPath) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw TraceProcessorInstallException(
        'download failed: HTTP ${response.statusCode} for $url',
      );
    }

    final tempFile = File('$destPath.download');
    try {
      final sink = tempFile.openWrite();
      try {
        await sink.addStream(response);
      } finally {
        await sink.close();
      }
      await tempFile.rename(destPath);
    } catch (_) {
      if (tempFile.existsSync()) await tempFile.delete();
      rethrow;
    }
  } finally {
    client.close(force: true);
  }
}
