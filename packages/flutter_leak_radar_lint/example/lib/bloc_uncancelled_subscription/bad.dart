// example/lib/bloc_uncancelled_subscription/bad.dart
import 'dart:async';
import 'package:bloc/bloc.dart';

// .listen() assigned to a field in the constructor, never cancelled in close().
class CounterBloc extends Cubit<int> {
  CounterBloc(Stream<int> ticks) : super(0) {
    // expect_lint: bloc_uncancelled_subscription
    _sub = ticks.listen(emit);
  }

  StreamSubscription<int>? _sub;
  // Missing close() override with _sub?.cancel().
}
