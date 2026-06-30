// lib/src/ui/widgets/startup_tab.dart
import 'package:flutter/material.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:radar_ui/radar_ui.dart';

// ── Startup key constants (match PerfEngine) ──────────────────────────────────

/// The span key name emitted by PerfEngine for the startup span.
const String _kStartupKeyName = 'startup';

/// The span category emitted by PerfEngine for the startup span.
const String _kStartupKeyCategory = 'perf_radar';

// ── Public widget ─────────────────────────────────────────────────────────────

/// Startup sub-tab.
///
/// When the startup span has been recorded (via PerfEngine's
/// `addPostFrameCallback`), shows the big "Time to first frame" headline
/// and an honest note explaining that per-phase breakdown requires
/// explicit instrumentation.
///
/// When no startup data is present, shows a dashed ∅ not-measured state
/// with guidance — never fabricates a number.
class StartupTab extends StatelessWidget {
  /// Creates a [StartupTab] from the current [snapshot].
  const StartupTab({super.key, required this.snapshot});

  /// The trace snapshot to read startup timing from.
  final TraceSnapshot snapshot;

  static const _startupKey = TraceKey(
    name: _kStartupKeyName,
    category: _kStartupKeyCategory,
  );

  SpanKeyStatsSnapshot? get _startupStats => snapshot.stats[_startupKey];

  @override
  Widget build(BuildContext context) {
    final stats = _startupStats;
    if (stats == null || stats.count == 0) {
      return const _NotMeasuredState();
    }
    return _MeasuredState(stats: stats);
  }
}

// ── Measured state ────────────────────────────────────────────────────────────

/// Shows the single measured startup span as a TTF headline.
///
/// The engine records one startup span — that is the only honest startup
/// datum available. Per-phase breakdown is not instrumented by default;
/// users are directed to [PerfRadar.trace] for that detail.
class _MeasuredState extends StatelessWidget {
  const _MeasuredState({required this.stats});

  final SpanKeyStatsSnapshot stats;

  String _fmtMs(int micros) {
    if (micros < 1000) return '$microsμs';
    return '${(micros / 1000).toStringAsFixed(0)}ms';
  }

  @override
  Widget build(BuildContext context) {
    final totalMicros = stats.meanMicros;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        20,
        12,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        // Big TTF headline
        Center(
          child: Text(_fmtMs(totalMicros), style: RadarTypography.metricHero),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('Time to first frame', style: RadarTypography.caption),
        ),
        const SizedBox(height: 20),

        // Honest note — no fabricated phase rows below this
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: RadarColors.bgSurface,
            borderRadius: RadarDensity.inputRadius,
            border: Border.all(color: RadarColors.hairline08),
          ),
          child: Text(
            'Per-phase breakdown is not instrumented. '
            'Wrap individual startup phases in PerfRadar.trace() '
            'to see a real breakdown.',
            style: RadarTypography.caption,
          ),
        ),
      ],
    );
  }
}

// ── Not-measured state ────────────────────────────────────────────────────────

/// Shown when no startup span has been recorded.
///
/// Per spec: dashed ∅ marker + guidance. Never fabricates a number.
class _NotMeasuredState extends StatelessWidget {
  const _NotMeasuredState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dashed ∅ marker
            CustomPaint(
              size: const Size(56, 56),
              painter: _DashedCirclePainter(),
              child: const SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: Text(
                    '∅',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 24,
                      color: RadarColors.text25,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Startup not measured',
              style: RadarTypography.monoBody.copyWith(
                fontWeight: FontWeight.w600,
                color: RadarColors.text60,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'To measure startup time, initialize PerfRadar before '
              'calling runApp():\n\n'
              'void main() async {\n'
              '  WidgetsFlutterBinding.ensureInitialized();\n'
              '  await PerfRadar.init(...);\n'
              '  runApp(MyApp());\n'
              '}',
              textAlign: TextAlign.left,
              style: RadarTypography.monoCode.copyWith(
                color: RadarColors.text40,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = RadarColors.text25
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashCount = 12;
    const dashGap = 0.18;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    const fullAngle = 3.14159265 * 2;
    const dashAngle = (fullAngle / dashCount) * (1 - dashGap);

    for (var i = 0; i < dashCount; i++) {
      final startAngle = (i * fullAngle / dashCount) - fullAngle / 4;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
