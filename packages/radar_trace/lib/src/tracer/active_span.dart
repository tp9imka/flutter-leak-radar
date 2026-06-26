import 'dart:async';

import '../model/span.dart';

/// Zone value key for the current active [Span].
///
/// Using a private-typed `Object` instance (not a string) as the key
/// prevents any accidental collision with user-defined Zone values.
const Object kActiveSpanKey = _ActiveSpanKey();

final class _ActiveSpanKey {
  const _ActiveSpanKey();
}

/// Returns the [Span] currently active in the ambient [Zone], or null
/// if no tracer span is in scope.
Span? get activeSpan => Zone.current[kActiveSpanKey] as Span?;
