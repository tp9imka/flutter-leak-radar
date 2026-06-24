import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../leak_radar.dart';
import '../model/leak_finding.dart';
import 'export_sheet.dart';
import '../model/leak_kind.dart';
import '../model/retaining_path.dart';
import 'theme/theme.dart';

/// Detail screen for a single [LeakFinding].
///
/// Shows live count, net growth, first-seen timestamp, a bar chart of the
/// capture history, a lazily-fetched retaining path, and a heap-capture action.
class FindingDetailScreen extends StatefulWidget {
  const FindingDetailScreen({super.key, required this.finding});

  final LeakFinding finding;

  @override
  State<FindingDetailScreen> createState() => _FindingDetailScreenState();
}

class _FindingDetailScreenState extends State<FindingDetailScreen> {
  bool _fetchingPath = false;
  bool _fetchedPath = false;
  RetainingPathView? _path;

  @override
  void initState() {
    super.initState();
    _fetchPath();
  }

  Future<void> _fetchPath() async {
    setState(() => _fetchingPath = true);
    final path =
        await LeakRadar.fetchRetainingPath(widget.finding.className);
    if (!mounted) return;
    setState(() {
      _fetchingPath = false;
      _fetchedPath = true;
      _path = path;
    });
  }

  Future<void> _captureHeap() async {
    final path = await LeakRadar.captureHeapSnapshotToFile();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path != null ? 'Saved: $path' : 'unavailable'),
      backgroundColor: LeakRadarColors.appBarBg,
    ));
  }

  void _showExportSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.55),
      isScrollControlled: true,
      builder: (_) => const LeakExportSheet(),
    );
  }

  int get _growth {
    final s = widget.finding.series;
    if (s.length > 1) return s.last - s.first;
    if (s.isNotEmpty) return s.last;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LeakRadarColors.pageBg,
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _buildSeverityStrip(),
          _buildStatCards(),
          widget.finding.series.isEmpty
              ? _buildPrecisePanel()
              : _buildBarChart(),
          _buildRetainingPath(),
          _buildBottomRow(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
        backgroundColor: LeakRadarColors.appBarBg,
        elevation: 0,
        title: Text(
          widget.finding.className,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          _IconBtn(
            icon: Icons.ios_share_outlined,
            tooltip: 'Share',
            onTap: () => _showExportSheet(context),
          ),
          const SizedBox(width: 4),
        ],
      );

  Widget _buildSeverityStrip() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _SeverityTag(severity: widget.finding.severity),
            const SizedBox(width: 8),
            Text(
              widget.finding.series.isEmpty
                  ? 'still live after disposal'
                  : 'grew +$_growth over '
                      '${widget.finding.series.length} captures',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: LeakRadarColors.text40,
              ),
            ),
          ],
        ),
      );

  Widget _buildStatCards() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  label: 'LIVE NOW',
                  value: '${widget.finding.liveCount}',
                  valueColor:
                      severityTokens(widget.finding.severity).text,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'NET GROWTH',
                  value: widget.finding.series.isEmpty ? '—' : '+$_growth',
                  valueColor: LeakRadarColors.text100,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'FIRST SEEN',
                  value: _formatFirstSeen(widget.finding.firstSeen),
                  valueColor: LeakRadarColors.text100,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildBarChart() {
    final tokens = severityTokens(widget.finding.severity);
    final times = widget.finding.captureTimes;
    final s = widget.finding.series;

    final firstLabel = times.isNotEmpty ? _formatCaptureLabel(times.first) : '—';
    final lastLabel = times.isNotEmpty ? _formatCaptureLabel(times.last) : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: LeakRadarColors.cardBg,
          border: Border.all(color: LeakRadarColors.border08),
          borderRadius: BorderRadius.circular(13),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live instances / capture',
              style: LeakRadarText.title.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: LeakRadarColors.text40,
                ),
                children: [
                  const TextSpan(text: 'never returns '),
                  TextSpan(
                    text: '↑',
                    style: TextStyle(color: tokens.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: CustomPaint(
                painter: _BarChartPainter(
                  series: s,
                  severityColor: tokens.text,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  firstLabel,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    color: LeakRadarColors.text25,
                  ),
                ),
                Flexible(
                  child: Text(
                    'forced GC between captures',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      color: LeakRadarColors.text25,
                    ),
                  ),
                ),
                Text(
                  lastLabel,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    color: LeakRadarColors.text25,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrecisePanel() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: LeakRadarColors.cardBg,
            border: Border.all(color: LeakRadarColors.border08),
            borderRadius: BorderRadius.circular(13),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Precise tracking',
                style: LeakRadarText.title.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Confirmed still live after disposal via WeakReference '
                'tracking. Precise findings carry no capture history — the '
                'retaining path below explains what holds the object.',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  height: 1.5,
                  color: LeakRadarColors.text40,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildRetainingPath() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: LeakRadarColors.codePreviewBg,
            border: Border.all(color: LeakRadarColors.border08),
            borderRadius: BorderRadius.circular(13),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.link,
                    color: LeakRadarColors.severityInfo,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Retaining path',
                        style: LeakRadarText.mono.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text('lazily fetched', style: LeakRadarText.label),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildPathBody(),
            ],
          ),
        ),
      );

  Widget _buildPathBody() {
    if (_fetchingPath) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: LeakRadarColors.accent,
          ),
        ),
      );
    }
    if (_fetchedPath && _path == null) {
      return Text('retaining path unavailable', style: LeakRadarText.label);
    }
    if (_path != null) return _buildPath(_path!);
    return const SizedBox.shrink();
  }

  Widget _buildPath(RetainingPathView path) {
    final tokens = severityTokens(widget.finding.severity);
    final rows = <Widget>[];

    if (path.gcRootType != null) {
      rows.add(_PathLine(
        connector: '',
        label: path.gcRootType!,
        labelColor: LeakRadarColors.text40,
      ));
    }

    for (final hop in path.elements) {
      final label = [
        if (hop.field != null) hop.field!,
        hop.objectType,
      ].join(' → ');
      rows.add(_PathLine(
        connector: '└─',
        label: label,
        labelColor: LeakRadarColors.severityInfo,
      ));
    }

    rows.add(_PathLine(
      connector: '└─',
      label: '${widget.finding.className} ← leaked',
      labelColor: tokens.text,
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _buildBottomRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: LeakRadarColors.cardBg,
                  border: Border.all(color: LeakRadarColors.border08),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('STATUS', style: LeakRadarText.label),
                    const SizedBox(height: 2),
                    Text(
                      widget.finding.tag != null
                          ? 'Tracked'
                          : 'Heap-inspected · no opt-in needed',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: LeakRadarColors.text80,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _captureHeap,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(90, 209, 230, 0.12),
                  border: Border.all(
                    color: const Color.fromRGBO(90, 209, 230, 0.30),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_outlined,
                      size: 14,
                      color: LeakRadarColors.severityInfo,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Capture .dartheap',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: LeakRadarColors.severityInfo,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatFirstSeen(DateTime? dt) {
  if (dt == null) return '—';
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String _formatCaptureLabel(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// ── Private widgets ───────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: LeakRadarDimens.iconButtonSize,
            height: LeakRadarDimens.iconButtonSize,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: LeakRadarDimens.iconButtonBg,
              border: Border.all(color: LeakRadarDimens.iconButtonBorder),
              borderRadius: BorderRadius.circular(
                LeakRadarDimens.iconButtonRadius,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: onTap != null
                  ? LeakRadarColors.text100
                  : LeakRadarColors.text25,
            ),
          ),
        ),
      );
}

class _SeverityTag extends StatelessWidget {
  const _SeverityTag({required this.severity});

  final LeakSeverity severity;

  @override
  Widget build(BuildContext context) {
    final tokens = severityTokens(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.tagBg,
        border: Border.all(color: tokens.tagBorder),
        borderRadius: BorderRadius.circular(LeakRadarTheme.tagRadius),
      ),
      child: Text(
        severity.name.toUpperCase(),
        style: LeakRadarText.severityTag,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: LeakRadarColors.cardBg,
          border: Border.all(color: LeakRadarColors.border08),
          borderRadius: BorderRadius.circular(13),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: LeakRadarColors.text25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
}

class _PathLine extends StatelessWidget {
  const _PathLine({
    required this.connector,
    required this.label,
    required this.labelColor,
  });

  final String connector;
  final String label;
  final Color labelColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (connector.isNotEmpty) ...[
              Text(
                connector,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: LeakRadarColors.text15,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: labelColor,
                ),
              ),
            ),
          ],
        ),
      );
}

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({
    required this.series,
    required this.severityColor,
  });

  final List<int> series;
  final Color severityColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final maxVal = series.reduce((a, b) => a > b ? a : b);
    final n = series.length;
    const gap = 6.0;
    final barWidth = (size.width - gap * (n - 1)) / n;

    for (var i = 0; i < n; i++) {
      final barHeight =
          maxVal == 0 ? 4.0 : size.height * series[i] / maxVal;
      final x = i * (barWidth + gap);
      final y = size.height - barHeight;
      final isLast = i == n - 1;
      final color = isLast
          ? severityColor
          : const Color.fromRGBO(255, 255, 255, 0.12);
      final rr = RRect.fromLTRBAndCorners(
        x,
        y,
        x + barWidth,
        size.height,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rr, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.series != series || old.severityColor != severityColor;
}
