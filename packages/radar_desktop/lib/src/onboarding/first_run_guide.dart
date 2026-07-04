import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'first_run_guide_controller.dart';
import 'guide_callout_layout.dart';
import 'guide_copy.dart';
import 'guide_spotlight_painter.dart';
import 'guide_widgets.dart';

export 'first_run_guide_controller.dart';

/// One of the six spotlight anchors the guide can point at.
///
/// [performance] and [stability] are spotlighted together on step 3 (the
/// overlay unions their two measured rects) — they're separate keys
/// because they're separate rail groups, each independently anchored.
enum GuideStep { connectBar, memory, performance, stability, android, tools }

/// The first-run tour's overlay: a welcome modal, five spotlight
/// coach-marks over the real shell, then a finish modal.
///
/// Self-hides (`SizedBox.shrink`) whenever `controller.open` is false.
/// [anchors] supplies a [GlobalKey] per [GuideStep]; the overlay measures
/// each key's render box to place its cut-out ring and callout — no
/// hard-coded coordinates, since the rail scrolls and the window
/// resizes. A missing or not-yet-laid-out anchor degrades gracefully:
/// the ring is skipped and the callout centers itself instead of
/// crashing.
class FirstRunGuide extends StatefulWidget {
  const FirstRunGuide({
    super.key,
    required this.controller,
    required this.anchors,
  });

  final FirstRunGuideController controller;
  final Map<GuideStep, GlobalKey> anchors;

  @override
  State<FirstRunGuide> createState() => _FirstRunGuideState();
}

class _FirstRunGuideState extends State<FirstRunGuide>
    with SingleTickerProviderStateMixin {
  final GlobalKey _rootKey = GlobalKey();
  final FocusNode _focusNode = FocusNode(debugLabel: 'FirstRunGuide');

  /// Drives the ring's glow pulse; null (and never started) under
  /// reduced motion.
  AnimationController? _pulse;
  bool _reduceMotion = false;

  /// The step a remeasure post-frame callback was last scheduled for —
  /// guards against scheduling one every build when an anchor genuinely
  /// never resolves (e.g. a key missing from [FirstRunGuide.anchors]).
  int? _lastRemeasureStep;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion != _reduceMotion || (!reduceMotion && _pulse == null)) {
      _reduceMotion = reduceMotion;
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (_reduceMotion) {
      _pulse?.dispose();
      _pulse = null;
      return;
    }
    _pulse ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _requestFocusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _scheduleRemeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// The measured rect of [anchorStep] in this overlay's own coordinate
  /// space, or null if either the overlay or the anchor hasn't been
  /// laid out yet.
  Rect? _measure(GuideStep anchorStep) {
    final anchorKey = widget.anchors[anchorStep];
    final overlayObject = _rootKey.currentContext?.findRenderObject();
    final anchorObject = anchorKey?.currentContext?.findRenderObject();
    if (overlayObject is! RenderBox || !overlayObject.hasSize) return null;
    if (anchorObject is! RenderBox || !anchorObject.hasSize) return null;
    final topLeft = anchorObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    return topLeft & anchorObject.size;
  }

  Rect? _union(Rect? a, Rect? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.expandToInclude(b);
  }

  /// The cut-out rect for spotlight [step] (1..5), or null for the
  /// welcome/finish steps or an anchor that hasn't resolved yet. Step 3
  /// unions the performance and stability rail groups.
  Rect? _rectForStep(int step) => switch (step) {
    1 => _measure(GuideStep.connectBar),
    2 => _measure(GuideStep.memory),
    3 => _union(_measure(GuideStep.performance), _measure(GuideStep.stability)),
    4 => _measure(GuideStep.android),
    5 => _measure(GuideStep.tools),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (!controller.open) return const SizedBox.shrink();
        _requestFocusSoon();
        return _buildOpen(controller);
      },
    );
  }

  Widget _buildOpen(FirstRunGuideController controller) {
    final step = controller.step;
    final isSpotlight =
        step >= 1 && step <= FirstRunGuideController.lastSpotlight;
    final rect = isSpotlight ? _rectForStep(step) : null;
    if (isSpotlight && rect == null && _lastRemeasureStep != step) {
      _lastRemeasureStep = step;
      _scheduleRemeasure();
    }

    return SizedBox.expand(
      key: _rootKey,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): controller.skip,
          const SingleActivator(LogicalKeyboardKey.arrowRight): controller.next,
          const SingleActivator(LogicalKeyboardKey.enter): controller.next,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): controller.back,
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: controller.skip,
                child: _buildBackdrop(rect),
              ),
              _buildForeground(controller, step, rect),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackdrop(Rect? rect) {
    // `TweenAnimationBuilder` asserts a non-null `tween.end`; a null rect
    // (welcome/finish, or a spotlight anchor not yet measured) has
    // nothing to tween towards, so paint it directly with no ring.
    if (rect == null) return _paintBackdrop(null);
    // `begin` and `end` both equal `rect` here, but this isn't a no-op:
    // `TweenAnimationBuilder` only honors a tween's `end` after the
    // first frame — on every later rebuild it animates from the
    // previous `end` towards the new one — so this is what drives the
    // ring's position sweep between spotlight steps.
    return TweenAnimationBuilder<Rect?>(
      tween: RectTween(begin: rect, end: rect),
      duration: _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, animatedRect, _) => _paintBackdrop(animatedRect),
    );
  }

  Widget _paintBackdrop(Rect? animatedRect) {
    final pulse = _pulse;
    if (pulse == null) {
      return CustomPaint(
        painter: GuideSpotlightPainter(
          cutout: animatedRect,
          reduceMotion: true,
        ),
      );
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) => CustomPaint(
        painter: GuideSpotlightPainter(
          cutout: animatedRect,
          glowStrength: pulse.value,
        ),
      ),
    );
  }

  Widget _buildForeground(
    FirstRunGuideController controller,
    int step,
    Rect? rect,
  ) {
    if (step == 0) {
      return GuideWelcomeCard(
        onSkip: controller.skip,
        onStart: controller.next,
      );
    }
    if (step > FirstRunGuideController.lastSpotlight) {
      return GuideFinishCard(
        onSkip: controller.skip,
        onBack: controller.back,
        onDone: controller.complete,
      );
    }
    return CustomSingleChildLayout(
      delegate: GuideCalloutLayoutDelegate(
        anchor: rect,
        preferBelow: step == 1,
      ),
      child: GuideSpotlightCallout(
        copy: guideSpotlightCopy[step]!,
        step: step,
        onSkip: controller.skip,
        onBack: controller.back,
        onNext: controller.next,
      ),
    );
  }
}
