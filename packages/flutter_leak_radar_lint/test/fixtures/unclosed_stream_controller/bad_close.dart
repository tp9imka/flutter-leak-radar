// test/fixtures/unclosed_stream_controller/bad_close.dart
// A BlocBase subclass whose StreamController field is never closed in close().
// The lint MUST fire; no synthesis auto-fix must be emitted (close() is async,
// so a trivial synthesis would be incorrect).
import 'dart:async';
import 'package:bloc/bloc.dart';

class _BadBloc extends Cubit<int> {
  _BadBloc() : super(0);

  // expect_lint: unclosed_stream_controller
  final _controller = StreamController<int>();
  // Missing close() override with _controller.close().
}
