// lib/src/util/type_checkers.dart
import 'package:custom_lint_builder/custom_lint_builder.dart';

// Flutter SDK disposable controller types.
// TypeChecker.fromName is correct for package: libraries.
const kAnimationControllerChecker = TypeChecker.fromName(
  'AnimationController',
  packageName: 'flutter',
);
const kTextEditingControllerChecker = TypeChecker.fromName(
  'TextEditingController',
  packageName: 'flutter',
);
const kScrollControllerChecker = TypeChecker.fromName(
  'ScrollController',
  packageName: 'flutter',
);
const kTabControllerChecker = TypeChecker.fromName(
  'TabController',
  packageName: 'flutter',
);
const kPageControllerChecker = TypeChecker.fromName(
  'PageController',
  packageName: 'flutter',
);
const kFocusNodeChecker = TypeChecker.fromName(
  'FocusNode',
  packageName: 'flutter',
);

const kControllerTypes = [
  kAnimationControllerChecker,
  kTextEditingControllerChecker,
  kScrollControllerChecker,
  kTabControllerChecker,
  kPageControllerChecker,
  kFocusNodeChecker,
];

// dart:async types.
//
// TypeChecker.fromUrl is used here because dart:* libraries are SDK
// libraries, not pub packages. Their URI scheme is 'dart:', not 'package:',
// so TypeChecker.fromName with packageName: 'async' cannot be relied upon —
// the packageName check inside _PackageChecker compares
// `uri.pathSegments.firstOrNull`, which for 'dart:async' yields 'async'
// and would technically match, but the fromUrl form is the explicitly
// documented and stable way to reference dart: SDK types. See the
// TypeChecker source comment: "it is in a stable package like in the
// dart: SDK."
//
// URL format: 'dart:<library>#<ClassName>'
const kStreamSubscriptionChecker = TypeChecker.fromUrl(
  'dart:async#StreamSubscription',
);
const kStreamChecker = TypeChecker.fromUrl('dart:async#Stream');
const kTimerChecker = TypeChecker.fromUrl('dart:async#Timer');
