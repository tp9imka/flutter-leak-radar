// test/fixtures/uncancelled_timer/bad_close.dart
// A BlocBase subclass whose Timer field is never cancelled in close().
// The lint MUST fire; no synthesis auto-fix must be emitted (close() is async).
import 'dart:async';
import 'package:bloc/bloc.dart';

class _BadTimerBloc extends Cubit<int> {
  _BadTimerBloc() : super(0);

  // expect_lint: uncancelled_timer
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  // Missing close() override with _timer?.cancel().
}
