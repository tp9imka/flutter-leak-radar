// test/fixtures/uncancelled_subscription/bad_close.dart
// A BlocBase subclass whose StreamSubscription field is never cancelled in
// close(). The lint MUST fire; no synthesis auto-fix must be emitted (close()
// is async, so a trivial synthesis would be incorrect).
import 'dart:async';
import 'package:bloc/bloc.dart';

class _BadBloc extends Cubit<int> {
  _BadBloc() : super(0);

  // expect_lint: uncancelled_subscription
  StreamSubscription<int>? _sub;

  void start() {
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }
  // Missing close() override with _sub?.cancel().
}
