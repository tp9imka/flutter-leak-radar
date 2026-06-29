// lib/src/widgets/radar_live_pulse_dot.dart

import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';

/// A slow pulsing dot indicating "live" or "connected" state.
///
/// Implements the `rdr-live` pulse from the design handoff: a soft
/// opacity pulse with a 2-second cycle. Animation is disabled when
/// [MediaQuery.disableAnimationsOf] returns `true` (accessibility
/// flag / reduced-motion preference).
class RadarLivePulseDot extends StatefulWidget {
  const RadarLivePulseDot({
    super.key,
    this.size = 8.0,
    this.color = RadarColors.accent,
  });

  /// Diameter of the dot in logical pixels.
  final double size;

  /// Fill color; defaults to [RadarColors.accent] (radar green).
  final Color color;

  @override
  State<RadarLivePulseDot> createState() => _RadarLivePulseDotState();
}

class _RadarLivePulseDotState extends State<RadarLivePulseDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      setState(_tearDown);
    } else {
      setState(_setUp);
    }
  }

  void _setUp() {
    if (_controller != null) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller!, curve: Curves.easeInOut));
  }

  void _tearDown() {
    _controller?.dispose();
    _controller = null;
    _opacity = null;
  }

  @override
  void dispose() {
    _tearDown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = SizedBox(
      width: widget.size,
      height: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );

    final anim = _opacity;
    if (anim == null) return dot;

    return FadeTransition(opacity: anim, child: dot);
  }
}
