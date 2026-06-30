// example/lib/showcase/good_screen.dart
//
// Contrast demo: the same resources as LeakyScreen, disposed correctly.
// Popping this screen produces zero Radar findings.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_radar/flutter_radar.dart';

/// Well-behaved screen with identical resources to [LeakyScreen].
///
/// Dispose is correct — Radar should produce zero findings after pop.
class GoodScreen extends StatefulWidget {
  const GoodScreen({super.key});

  @override
  State<GoodScreen> createState() => _GoodScreenState();
}

class _GoodScreenState extends State<GoodScreen> {
  final TextEditingController _textController = TextEditingController();
  final StreamController<int> _streamController = StreamController<int>();
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  StreamSubscription<int>? _subscription;
  Timer? _timer;

  void _onNotifierChanged() {}

  @override
  void initState() {
    super.initState();
    Radar.track(this, tag: 'GoodScreen');

    _subscription = Stream.periodic(
      const Duration(seconds: 1),
      (i) => i,
    ).listen((_) {});

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});

    _streamController.stream.listen((_) {});

    _notifier.addListener(_onNotifierChanged);
  }

  @override
  void dispose() {
    Radar.markDisposed(this);
    _textController.dispose();
    _subscription?.cancel();
    _timer?.cancel();
    _streamController.close();
    _notifier
      ..removeListener(_onNotifierChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Good Screen — properly disposed')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Same resources as LeakyScreen — all disposed correctly.\n\n'
              'Expected after pop: zero Radar findings for this screen.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'TextEditingController (will be disposed)',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pop this screen, then open Radar → Leaks tab.\n'
              'GoodScreen should produce no findings.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
