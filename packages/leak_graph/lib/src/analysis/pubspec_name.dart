import 'dart:convert';

/// Parses a pubspec.yaml's top-level `name:` scalar.
///
/// Only matches the key at column zero — a `name:` nested under another
/// section (e.g. inside `executables:`) is not the package name and is
/// skipped. Pure and dependency-free: this hand-rolled scan avoids pulling in
/// a YAML parser for a single scalar line, and stays web-safe (no `dart:io`)
/// so a DevTools extension can parse a pubspec it read over DTD.
String? packageNameFromPubspec(String pubspecYaml) {
  for (final line in const LineSplitter().convert(pubspecYaml)) {
    if (line.isEmpty || line[0] == ' ' || line[0] == '\t') continue;
    if (!line.startsWith('name:')) continue;

    var value = line.substring('name:'.length).trim();
    final commentIndex = value.indexOf('#');
    if (commentIndex >= 0) value = value.substring(0, commentIndex).trim();
    value = _unquote(value);
    return value.isEmpty ? null : value;
  }
  return null;
}

String _unquote(String value) {
  if (value.length < 2) return value;
  final isDoubleQuoted = value.startsWith('"') && value.endsWith('"');
  final isSingleQuoted = value.startsWith("'") && value.endsWith("'");
  if (isDoubleQuoted || isSingleQuoted) {
    return value.substring(1, value.length - 1);
  }
  return value;
}
