// example/lib/discarded_listen_result/good_assigned_local.dart
// Proves: assigning the .listen() result to a local variable does NOT trigger
// the discarded_listen_result lint (the result is not discarded).
import 'dart:async';

void example(Stream<int> stream) {
  // Assignment — not a bare ExpressionStatement.
  final sub = stream.listen((_) {});
  sub.cancel();
}
