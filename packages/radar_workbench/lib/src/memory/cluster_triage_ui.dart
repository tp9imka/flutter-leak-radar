part of 'leak_clusters_view.dart';

/// Thin bar above the cluster list carrying the "since last session" filter.
class _TriageToolbar extends StatelessWidget {
  const _TriageToolbar({
    required this.sinceLastSession,
    required this.onSinceLastSession,
  });

  final bool sinceLastSession;
  final ValueChanged<bool> onSinceLastSession;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RadarColors.bgPanel,
        border: Border(
          bottom: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Spacer(),
            _SinceLastSessionToggle(
              value: sinceLastSession,
              onChanged: onSinceLastSession,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact toggle pill: when on, the cluster list shows only signatures new
/// since the last session (GONE stays visible on its own).
class _SinceLastSessionToggle extends StatelessWidget {
  const _SinceLastSessionToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = value ? RadarColors.accent : RadarColors.text50;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: value ? RadarColors.accentSubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: RadarDensity.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              'Since last session',
              style: RadarTypography.monoLabel.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The payoff: leak signatures that were known last session and have
/// disappeared from the current heap — positive confirmation a fix landed.
/// Bounded + scrollable so a large batch of fixes never overflows the frame.
class _GoneSection extends StatelessWidget {
  const _GoneSection({required this.entries});

  static const double _maxHeight = 148;

  final List<TriageEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: RadarColors.accent.withValues(alpha: 0.10),
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: RadarColors.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  // The header stays date-agnostic; each row carries the
                  // honest per-entry "fixed since <date>". Some GONE entries
                  // may be older than the last session.
                  'Fixed · ${entries.length}',
                  style: RadarTypography.monoLabel.copyWith(
                    color: RadarColors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: _GoneRow(entry: entry),
              ),
          ],
        ),
      ),
    );
  }
}

/// One fixed-signature line: what was fixed (class name, else note, else the
/// raw signature) plus an honest `fixed since <date>` when the retirement date
/// is known (it is stamped on the next save, so it may be absent the very first
/// session a fix is observed).
class _GoneRow extends StatelessWidget {
  const _GoneRow({required this.entry});

  final TriageEntry entry;

  @override
  Widget build(BuildContext context) {
    final label = entry.className ?? entry.note ?? entry.signature;
    final since = entry.goneSince;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: RadarTypography.monoLabel.copyWith(
              color: RadarColors.text60,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          since == null ? 'fixed' : 'fixed since ${_fmtDate(since)}',
          style: RadarTypography.monoLabel.copyWith(color: RadarColors.accent),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime dt) {
  final local = dt.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// The per-row overflow menu carrying the ACK action.
enum _TriageAction { acknowledge }

class _AckMenuButton extends StatelessWidget {
  const _AckMenuButton({required this.display, required this.onAcknowledge});

  final TriageDisplay display;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final acked = display == TriageDisplay.acknowledged;
    return PopupMenuButton<_TriageAction>(
      tooltip: 'Triage actions',
      padding: EdgeInsets.zero,
      iconSize: 16,
      icon: const Icon(Icons.more_vert, color: RadarColors.text40),
      onSelected: (action) => switch (action) {
        _TriageAction.acknowledge => onAcknowledge(),
      },
      itemBuilder: (context) => [
        PopupMenuItem<_TriageAction>(
          value: _TriageAction.acknowledge,
          child: Text(acked ? 'Edit note…' : 'Acknowledge…'),
        ),
      ],
    );
  }
}

/// Result of the ACK note prompt: whether the user confirmed, and the note.
typedef _AckResult = ({bool confirmed, String? note});

/// Shows a dialog to acknowledge [cluster] with an optional note. Returns
/// `confirmed: false` on cancel or barrier dismiss.
Future<_AckResult> _promptForNote(
  BuildContext context,
  GraphLeakCluster cluster,
) async {
  // Confirm pops the trimmed note text (possibly empty); cancel / dismiss pops
  // null. That distinguishes "acknowledged with no note" from "cancelled".
  final text = await showDialog<String>(
    context: context,
    builder: (context) => _AckNoteDialog(className: cluster.className),
  );
  if (text == null) return (confirmed: false, note: null);
  return (confirmed: true, note: text.isEmpty ? null : text);
}

/// The ACK note dialog. Owns its [TextEditingController] so it is disposed only
/// when the route is removed — disposing it eagerly after `showDialog`
/// completes crashes the pending caret callback.
class _AckNoteDialog extends StatefulWidget {
  const _AckNoteDialog({required this.className});

  final String className;

  @override
  State<_AckNoteDialog> createState() => _AckNoteDialogState();
}

class _AckNoteDialogState extends State<_AckNoteDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Acknowledge ${widget.className}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Note (optional)',
          hintText: 'e.g. tracked in TICKET-123',
        ),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _confirm, child: const Text('Acknowledge')),
      ],
    );
  }
}
