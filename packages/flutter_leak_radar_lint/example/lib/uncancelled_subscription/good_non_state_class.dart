// example/lib/uncancelled_subscription/good_non_state_class.dart
// Proves: a StreamSubscription field in a plain Dart class (not State or
// BlocBase) is NOT flagged — the rule only applies to classes with a
// known teardown method.
import 'dart:async';

class MyService {
  StreamSubscription<int>? _sub;

  void start(Stream<int> stream) {
    _sub = stream.listen((_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
