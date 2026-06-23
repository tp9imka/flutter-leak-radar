// Fixture: field not disposed in teardown — used by rule tests transitively.
import 'dart:async';
import 'package:flutter/widgets.dart';

class BadWidget extends StatefulWidget {
  const BadWidget({super.key});
  @override
  State<BadWidget> createState() => _BadWidgetState();
}

class _BadWidgetState extends State<BadWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream<int>.empty().listen((_) {});
  }

  @override
  void dispose() {
    // _sub.cancel() intentionally omitted — bad case
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
