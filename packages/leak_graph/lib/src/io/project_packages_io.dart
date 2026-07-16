import 'dart:convert';
import 'dart:io';

/// Parses a pubspec.yaml's top-level `name:` scalar.
///
/// Only matches the key at column zero — a `name:` nested under another
/// section (e.g. inside `executables:`) is not the package name and is
/// skipped. Pure and dependency-free: this hand-rolled scan avoids pulling in
/// a YAML parser for a single scalar line.
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

/// The root package name plus every workspace/melos member package name
/// found under [rootDir].
///
/// Members are read from `packages/*/pubspec.yaml` under [rootDir]. Never
/// throws: a missing [rootDir], a missing `pubspec.yaml`, or a pubspec with
/// no `name:` line are all treated as "no name to contribute" rather than an
/// error, so a caller always gets a (possibly empty) result.
Future<Set<String>> projectPackagesFromDir(String rootDir) async {
  final names = <String>{};

  final rootName = await _packageNameFromFile(_join(rootDir, 'pubspec.yaml'));
  if (rootName != null) names.add(rootName);

  final membersDir = Directory(_join(rootDir, 'packages'));
  if (await membersDir.exists()) {
    await for (final entry in membersDir.list()) {
      if (entry is! Directory) continue;
      final memberName = await _packageNameFromFile(
        _join(entry.path, 'pubspec.yaml'),
      );
      if (memberName != null) names.add(memberName);
    }
  }

  return Set.unmodifiable(names);
}

Future<String?> _packageNameFromFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  try {
    return packageNameFromPubspec(await file.readAsString());
  } on Exception {
    return null;
  }
}

String _join(String base, String child) =>
    base.endsWith('/') ? '$base$child' : '$base/$child';
