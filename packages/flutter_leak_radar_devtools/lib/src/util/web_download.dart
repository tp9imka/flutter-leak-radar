import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [json] pretty-printed as a `.json` file.
///
/// The DevTools extension runs in a web (Chrome) context, so this builds a
/// Blob, hands it an object URL, and clicks a synthetic anchor.
void downloadJson(String filename, Object? json) {
  final text = const JsonEncoder.withIndent('  ').convert(json);
  final parts = <JSAny>[text.toJS].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: 'application/json'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
