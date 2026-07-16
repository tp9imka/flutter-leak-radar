import 'dart:io';

import '../analysis/pubspec_name.dart';

export '../analysis/pubspec_name.dart' show packageNameFromPubspec;

/// The root package name plus every workspace/melos member package name
/// found under [rootDir].
///
/// Members are read from `packages/*/pubspec.yaml` under [rootDir]. Never
/// throws: a missing [rootDir], a missing `pubspec.yaml`, a pubspec with no
/// `name:` line, or an unreadable `packages/` directory (e.g. permission
/// denied) are all treated as "no name to contribute" rather than an error,
/// so a caller always gets a (possibly empty) result built from whatever
/// could actually be read.
Future<Set<String>> projectPackagesFromDir(String rootDir) async {
  final names = <String>{};

  final rootName = await _packageNameFromFile(_join(rootDir, 'pubspec.yaml'));
  if (rootName != null) names.add(rootName);

  final membersDir = Directory(_join(rootDir, 'packages'));
  if (await membersDir.exists()) {
    try {
      await for (final entry in membersDir.list()) {
        if (entry is! Directory) continue;
        final memberName = await _packageNameFromFile(
          _join(entry.path, 'pubspec.yaml'),
        );
        if (memberName != null) names.add(memberName);
      }
    } on Exception {
      // Unreadable packages/ dir (e.g. permission denied): degrade to
      // whatever was already gathered rather than throwing.
    }
  }

  return Set.unmodifiable(names);
}

Future<String?> _packageNameFromFile(String path) async {
  final file = File(path);
  try {
    if (!await file.exists()) return null;
    return packageNameFromPubspec(await file.readAsString());
  } on Exception {
    return null;
  }
}

String _join(String base, String child) =>
    base.endsWith('/') ? '$base$child' : '$base/$child';
