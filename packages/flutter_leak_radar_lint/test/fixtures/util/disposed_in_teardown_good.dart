// Fixture: field properly disposed in teardown.
import 'dart:async';
import 'package:flutter/widgets.dart';

class GoodWidget extends StatefulWidget {
  const GoodWidget({super.key});
  @override
  State<GoodWidget> createState() => _GoodWidgetState();
}

class _GoodWidgetState extends State<GoodWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream<int>.empty().listen((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
