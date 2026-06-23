// test/fixtures/bloc_uncancelled_subscription/good.dart
import 'dart:async';
import 'package:bloc/bloc.dart';

// Good: subscription assigned to a field and cancelled in close().
class _GoodBloc extends Cubit<int> {
  _GoodBloc(Stream<int> ticks) : super(0) {
    _sub = ticks.listen((v) => emit(v));
  }

  StreamSubscription<int>? _sub;

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

// Good: cancelled inside an if-block in close() — recursive walk.
class _GoodConditionalBloc extends Cubit<int> {
  _GoodConditionalBloc(Stream<int> ticks) : super(0) {
    _sub = ticks.listen((v) => emit(v));
  }

  StreamSubscription<int>? _sub;
  bool _active = true;

  @override
  Future<void> close() {
    if (_active) {
      _sub?.cancel();
    }
    return super.close();
  }
}

// Good: emit.forEach is managed by bloc's own lifecycle — never flagged.
class _GoodForEachBloc extends Cubit<int> {
  _GoodForEachBloc(this._ticks) : super(0);
  final Stream<int> _ticks;

  Future<void> watch() async {
    await emit.forEach<int>(_ticks, onData: (v) => v);
  }
}

// Good: emit.onEach is also managed by bloc — never flagged.
class _GoodOnEachBloc extends Cubit<int> {
  _GoodOnEachBloc(this._ticks) : super(0);
  final Stream<int> _ticks;

  Future<void> watch() async {
    await emit.onEach<int>(_ticks, onData: (v) {});
  }
}

// Good: .listen() is NOT in the constructor — out of this rule's scope. It is a
// field cancelled in close() anyway, so it is genuinely fine.
class _GoodMethodListenBloc extends Cubit<int> {
  _GoodMethodListenBloc() : super(0);

  StreamSubscription<int>? _sub;

  void start(Stream<int> ticks) {
    _sub = ticks.listen((v) => emit(v));
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

// Good: a non-Bloc class that calls .listen() in its constructor is NOT this
// rule's concern (the consumer may not even depend on bloc).
class PlainService {
  PlainService(Stream<int> ticks) {
    _sub = ticks.listen((_) {});
  }

  StreamSubscription<int>? _sub;

  void stop() {
    _sub?.cancel();
  }
}
