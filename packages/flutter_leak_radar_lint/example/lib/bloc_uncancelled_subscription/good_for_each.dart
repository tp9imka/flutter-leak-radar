// example/lib/bloc_uncancelled_subscription/good_for_each.dart
// Proves: emit.forEach / emit.onEach are bloc-managed lifecycle helpers, not
// author-owned subscriptions — they are NEVER flagged.
import 'package:bloc/bloc.dart';

class CounterBloc extends Cubit<int> {
  CounterBloc(this._ticks) : super(0);
  final Stream<int> _ticks;

  Future<void> watch() async {
    await emit.forEach<int>(_ticks, onData: (v) => v);
  }
}
