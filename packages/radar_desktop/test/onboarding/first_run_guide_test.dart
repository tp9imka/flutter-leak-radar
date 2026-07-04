import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/onboarding/first_run_guide.dart';
import 'package:radar_ui/radar_ui.dart';

/// In-memory [FirstRunStore] fake — no real fs/path_provider, mirrors
/// `first_run_guide_controller_test.dart`'s fake.
class _FakeFirstRunStore implements FirstRunStore {
  bool seen = false;
  int markSeenCount = 0;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async {
    seen = true;
    markSeenCount++;
  }
}

/// The harness's simulated window — set via `tester.view.physicalSize`
/// so it's the real constraint every widget lays out against (a
/// `MediaQueryData` override alone doesn't resize the actual surface).
const Size _windowSize = Size(1000, 700);

Map<GuideStep, GlobalKey> _buildAnchors() => {
  for (final step in GuideStep.values) step: GlobalKey(),
};

/// Six placeholder anchor boxes at known rects (standing in for the
/// connect bar + five rail groups) plus the guide overlay layered on
/// top, matching how `DesktopShell` will wire the real widgets in
/// Task 4.
Widget _harness(
  FirstRunGuideController controller,
  Map<GuideStep, GlobalKey> anchors, {
  bool disableAnimations = false,
}) {
  Widget anchor(GuideStep step, Rect rect) => Positioned(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
    child: KeyedSubtree(key: anchors[step], child: const SizedBox.expand()),
  );

  return MaterialApp(
    theme: radarDarkTheme(),
    home: Builder(
      // Overrides only `disableAnimations`, inheriting the real ambient
      // size driven by `tester.view.physicalSize` — a fresh
      // `MediaQueryData()` here would default `size` to `Size.zero` and
      // starve every width-dependent layout below.
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: Scaffold(
          body: Stack(
            children: [
              anchor(
                GuideStep.connectBar,
                const Rect.fromLTWH(12, 60, 400, 40),
              ),
              anchor(GuideStep.memory, const Rect.fromLTWH(12, 120, 180, 150)),
              anchor(
                GuideStep.performance,
                const Rect.fromLTWH(12, 280, 180, 90),
              ),
              anchor(
                GuideStep.stability,
                const Rect.fromLTWH(12, 380, 180, 90),
              ),
              anchor(GuideStep.android, const Rect.fromLTWH(12, 480, 180, 130)),
              anchor(GuideStep.tools, const Rect.fromLTWH(12, 620, 180, 40)),
              Positioned.fill(
                child: FirstRunGuide(controller: controller, anchors: anchors),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _FakeFirstRunStore store;
  late FirstRunGuideController controller;
  late Map<GuideStep, GlobalKey> anchors;

  setUp(() {
    store = _FakeFirstRunStore();
    controller = FirstRunGuideController(store: store);
    anchors = _buildAnchors();
  });

  /// Pumps the harness at a real [_windowSize] surface, then loads the
  /// (unseen) controller so the guide auto-opens at the welcome step.
  Future<void> pumpGuide(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = _windowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(controller, anchors, disableAnimations: disableAnimations),
    );
    await controller.load();
    await tester.pump();
  }

  testWidgets('welcome shows the headline, both buttons, and the fine print', (
    tester,
  ) async {
    await pumpGuide(tester);

    expect(find.text('Welcome to Radar Desktop'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
    expect(find.text('Take the tour →'), findsOneWidget);
    expect(
      find.text('Esc to skip · ← → to navigate · shown once.'),
      findsOneWidget,
    );
  });

  testWidgets('renders nothing when the controller has not been opened', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(controller, anchors));
    await tester.pump();

    expect(find.text('Welcome to Radar Desktop'), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('skip for now on welcome closes the guide and marks it seen', (
    tester,
  ) async {
    await pumpGuide(tester);

    await tester.tap(find.text('Skip for now'));
    await tester.pump();

    expect(controller.open, isFalse);
    expect(store.markSeenCount, 1);
  });

  testWidgets(
    'take the tour advances to step 1 with its copy and the 1 / 5 counter',
    (tester) async {
      await pumpGuide(tester);

      await tester.tap(find.text('Take the tour →'));
      await tester.pump();

      expect(find.text('Connect to a running app.'), findsOneWidget);
      expect(find.text('1 / 5'), findsOneWidget);
    },
  );

  testWidgets('next walks every spotlight to the finish step, '
      'Next reading Finish on step 5', (tester) async {
    await pumpGuide(tester);
    await tester.tap(find.text('Take the tour →'));
    await tester.pump();

    for (var step = 1; step < FirstRunGuideController.lastSpotlight; step++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
    }

    expect(find.text('External tools & the health dot.'), findsOneWidget);
    expect(find.text('5 / 5'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    await tester.tap(find.text('Finish'));
    await tester.pump();

    expect(find.text("You're set."), findsOneWidget);
  });

  testWidgets('done on the finish step closes the guide and marks it seen', (
    tester,
  ) async {
    await pumpGuide(tester);
    for (var i = 0; i <= FirstRunGuideController.lastSpotlight; i++) {
      controller.next();
    }
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(controller.open, isFalse);
    expect(store.markSeenCount, 1);
  });

  testWidgets('back on the finish step returns to step 5', (tester) async {
    await pumpGuide(tester);
    for (var i = 0; i <= FirstRunGuideController.lastSpotlight; i++) {
      controller.next();
    }
    await tester.pump();

    await tester.tap(find.text('Back'));
    await tester.pump();

    expect(controller.step, FirstRunGuideController.lastSpotlight);
    expect(find.text('External tools & the health dot.'), findsOneWidget);
  });

  testWidgets('skip on a spotlight step closes the guide', (tester) async {
    await pumpGuide(tester);
    controller.next();
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(controller.open, isFalse);
    expect(store.markSeenCount, 1);
  });

  testWidgets('tapping the dim backdrop skips the guide', (tester) async {
    await pumpGuide(tester);
    controller.next();
    await tester.pump();

    // Far corner of the 1000x700 harness, well clear of every anchor
    // rect and the callout (placed near the connect-bar anchor).
    await tester.tapAt(const Offset(990, 690));
    await tester.pump();

    expect(controller.open, isFalse);
  });

  testWidgets('escape skips the guide from the keyboard', (tester) async {
    await pumpGuide(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(controller.open, isFalse);
  });

  testWidgets('arrow right and enter advance; arrow left goes back', (
    tester,
  ) async {
    await pumpGuide(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.step, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.step, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.step, 1);
  });

  testWidgets('the warning-toned note shows on steps 3 and 5, not step 2', (
    tester,
  ) async {
    await pumpGuide(tester);
    controller
      ..next()
      ..next();
    await tester.pump();
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    controller.next();
    await tester.pump();
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      find.text('Locked now (offline) — connect via the bar above to unlock.'),
      findsOneWidget,
    );
  });

  testWidgets("step 1's note is accent-toned, not warning-toned (spec §3)", (
    tester,
  ) async {
    await pumpGuide(tester);
    await tester.tap(find.text('Take the tour →'));
    await tester.pump();

    expect(find.textContaining('unlocks Performance'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    controller
      ..next()
      ..next();
    await tester.pump();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('renders every step without throwing under reduced motion', (
    tester,
  ) async {
    await pumpGuide(tester, disableAnimations: true);
    expect(tester.takeException(), isNull);

    for (var step = 1; step <= FirstRunGuideController.lastSpotlight; step++) {
      controller.next();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    controller.next();
    await tester.pump();

    expect(find.text("You're set."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the callout for a spotlight step sits within the overlay bounds',
    (tester) async {
      await pumpGuide(tester);
      controller.next();
      await tester.pump();

      final rect = tester.getRect(find.byType(CustomSingleChildLayout));

      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1000));
      expect(rect.bottom, lessThanOrEqualTo(700));
    },
  );
}
