// example/lib/bloc_uncancelled_subscription/good.dart
import 'dart:async';
import 'package:bloc/bloc.dart';

// Good: subscription assigned to a field and cancelled in close().
class CounterBloc extends Cubit<int> {
  CounterBloc(Stream<int> ticks) : super(0) {
    _sub = ticks.listen(emit);
  }

  StreamSubscription<int>? _sub;

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
