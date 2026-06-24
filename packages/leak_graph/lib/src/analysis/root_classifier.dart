import '../model/root_kind.dart';

/// Classifies the root of a retaining path into a [RootKind].
///
/// [pathClassNames] is ordered root → object. Scans from the root end and
/// returns the first matching [RootKind]. Never returns [RootKind.liveTree].
RootKind classifyRoot(List<String> pathClassNames) {
  if (pathClassNames.isEmpty) return RootKind.other;

  for (final name in pathClassNames) {
    if (_isTimer(name)) return RootKind.timer;
    if (_isStream(name)) return RootKind.stream;
    if (_isFinalizer(name)) return RootKind.finalizer;
    if (_isClosure(name)) return RootKind.closure;
  }

  if (_isStaticOrGlobal(pathClassNames.first)) return RootKind.staticOrGlobal;

  return RootKind.other;
}

bool _isTimer(String name) => name == 'Timer' || name == '_Timer';

bool _isStream(String name) =>
    name.endsWith('StreamSubscription') || name.endsWith('StreamController');

bool _isFinalizer(String name) =>
    name == 'Finalizer' ||
    name == 'NativeFinalizer' ||
    name.endsWith('FinalizerEntry');

bool _isClosure(String name) =>
    name == '_Closure' ||
    name == 'Closure' ||
    name == 'Context' ||
    name == '_Context';

bool _isStaticOrGlobal(String name) =>
    name == 'Library' ||
    name == 'Class' ||
    name == 'Type' ||
    name == '_Type' ||
    name == 'PatchClass';
