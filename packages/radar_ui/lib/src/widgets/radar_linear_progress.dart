import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';

/// An indeterminate left-to-right sweep bar — the "analyzing…" affordance for
/// long background work (e.g. parsing a large heap dump).
///
/// Compositor-friendly: animates only a translated child, never layout.
class RadarLinearProgress extends StatefulWidget {
  const RadarLinearProgress({
    super.key,
    this.height = 2.0,
    this.color = RadarColors.accent,
    this.trackColor = RadarColors.hairline08,
  });

  final double height;
  final Color color;
  final Color trackColor;

  @override
  State<RadarLinearProgress> createState() => _RadarLinearProgressState();
}

class _RadarLinearProgressState extends State<RadarLinearProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: widget.trackColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 0.0;
              final barWidth = trackWidth * 0.4;
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // Sweep from off-left to off-right.
                  final travel = trackWidth + barWidth;
                  final dx = _controller.value * travel - barWidth;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: barWidth,
                        child: ColoredBox(color: widget.color),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
