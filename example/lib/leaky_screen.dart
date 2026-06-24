// example/lib/leaky_screen.dart
//
// Intentional leak testbed — demonstrates 6 lint-rule patterns in one State.
//
// Pattern 1  undisposed_controller      — TextEditingController created, never disposed
// Pattern 2  uncancelled_subscription   — StreamSubscription field, never cancelled
// Pattern 3  uncancelled_timer          — Timer.periodic field, never cancelled
// Pattern 4  unclosed_stream_controller — StreamController field, never closed
// Pattern 5  discarded_listen_result    — bare stream.listen() whose result is dropped
// Pattern 6  missing_remove_listener    — addListener without removeListener in dispose()
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

class LeakyScreen extends StatefulWidget {
  const LeakyScreen({super.key});

  @override
  State<LeakyScreen> createState() => _LeakyScreenState();
}

class _LeakyScreenState extends State<LeakyScreen> {
  // Pattern 1: undisposed_controller — TextEditingController never disposed.
  final TextEditingController _textController = TextEditingController();

  // Pattern 2: uncancelled_subscription — StreamSubscription never cancelled.
  StreamSubscription<int>? _subscription;

  // Pattern 3: uncancelled_timer — Timer.periodic never cancelled.
  Timer? _timer;

  // Pattern 4: unclosed_stream_controller — StreamController never closed.
  final StreamController<int> _streamController = StreamController<int>();

  // Pattern 6: missing_remove_listener — ValueNotifier addListener without removeListener.
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  void _onNotifierChanged() {}

  void _onTimer() {}

  void _onStream() {}

  @override
  void initState() {
    super.initState();
    LeakRadar.track(this, tag: 'LeakyScreen');

    // Pattern 2: assign subscription to field, never cancel it.
    _subscription = Stream.periodic(const Duration(seconds: 1), (i) => i).listen((_) {
      _onStream();
    });

    // Pattern 3: start periodic timer, never cancel it.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _onTimer();
    });

    // Pattern 5: discarded_listen_result — result of .listen() is not captured.
    _streamController.stream.listen((_) {});

    // Pattern 6: addListener with a named callback, no matching removeListener.
    _notifier.addListener(_onNotifierChanged);
  }

  @override
  void dispose() {
    // Tell Leak Radar this State should now be collectable. Because we skip
    // the teardown below, the live Timer/subscription keep it alive — so the
    // precise tracker reports it as a notGced leak on a single navigation.
    LeakRadar.markDisposed(this);
    // Intentionally NOT calling:
    //   _textController.dispose()    (pattern 1)
    //   _subscription?.cancel()      (pattern 2)
    //   _timer?.cancel()             (pattern 3)
    //   _streamController.close()    (pattern 4)
    //   _notifier.removeListener(…)  (pattern 6)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaky Screen — 6 patterns')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This screen intentionally leaks:\n'
              '  1. TextEditingController (undisposed_controller)\n'
              '  2. StreamSubscription (uncancelled_subscription)\n'
              '  3. Timer.periodic (uncancelled_timer)\n'
              '  4. StreamController (unclosed_stream_controller)\n'
              '  5. bare .listen() (discarded_listen_result)\n'
              '  6. addListener without removeListener (missing_remove_listener)',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Type something (controller leaks on pop)',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pop this screen, then open the Leak Radar dashboard\n'
              'or wait for the navigation-triggered scan.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
