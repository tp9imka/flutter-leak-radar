// test/fixtures/bloc_uncancelled_subscription/bad.dart
import 'dart:async';
import 'package:bloc/bloc.dart';

// Discarded .listen() in the constructor — no field, no way to cancel.
class _DiscardedBloc extends Cubit<int> {
  _DiscardedBloc(Stream<int> ticks) : super(0) {
    // expect_lint: bloc_uncancelled_subscription
    ticks.listen((v) => emit(v));
  }
}

// .listen() assigned to a field in the constructor, never cancelled in close().
class _FieldNoCloseBloc extends Cubit<int> {
  _FieldNoCloseBloc(Stream<int> ticks) : super(0) {
    // expect_lint: bloc_uncancelled_subscription
    _sub = ticks.listen((v) => emit(v));
  }

  StreamSubscription<int>? _sub;
  // Missing close() override with _sub?.cancel().
}

// .listen() assigned to a field, close() exists but does not cancel the sub.
class _FieldCloseNoCancelBloc extends Cubit<int> {
  _FieldCloseNoCancelBloc(Stream<int> ticks) : super(0) {
    // expect_lint: bloc_uncancelled_subscription
    _sub = ticks.listen((v) => emit(v));
  }

  StreamSubscription<int>? _sub;

  @override
  Future<void> close() {
    return super.close();
  }
}
