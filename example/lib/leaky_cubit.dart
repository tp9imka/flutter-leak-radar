// example/lib/leaky_cubit.dart
//
// Pattern 7: bloc_uncancelled_subscription
// A Cubit that starts a stream.listen() in its constructor and assigns the
// result to a field, but never cancels it in an overridden close().
import 'dart:async';

import 'package:bloc/bloc.dart';

class LeakyCubit extends Cubit<int> {
  LeakyCubit() : super(0) {
    // bloc_uncancelled_subscription: assigned to field in constructor,
    // but close() is never overridden to call _sub?.cancel().
    _sub = Stream.periodic(const Duration(seconds: 1), (i) => i).listen(emit);
  }

  StreamSubscription<int>? _sub;

  // Intentionally NOT overriding close() to cancel _sub.
}
