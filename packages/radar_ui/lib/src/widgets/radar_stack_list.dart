// lib/src/widgets/radar_stack_list.dart

import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';
import '../tokens/typography.dart';

/// A single line in a [RadarStackList]: a call-stack frame.
///
/// [text] is the frame symbol (e.g. `'flutter::Foo::bar'` or `'malloc'`).
/// [module] is the owning binary (e.g. `'libflutter.so'`), rendered dimmed
/// beside the symbol. [tag] is an optional trailing widget, such as a
/// fidelity `RadarTag`.
class RadarStackFrame {
  const RadarStackFrame({required this.text, this.module, this.tag});

  /// The frame symbol text.
  final String text;

  /// The owning module/binary name; shown dimmed next to [text].
  final String? module;

  /// Optional trailing widget for this frame (e.g. a fidelity tag).
  final Widget? tag;
}

/// A native/dart call stack rendered as a code block.
///
/// Renders [RadarColors.bgCode] background with one monospaced line per
/// [RadarStackFrame]. When [frames] is empty, shows a "no frames"
/// placeholder instead of an empty block.
class RadarStackList extends StatelessWidget {
  const RadarStackList({super.key, required this.frames});

  /// The call-stack frames to render, in order.
  final List<RadarStackFrame> frames;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgCode,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RadarDensity.rowHPad,
          vertical: RadarDensity.rowVPad,
        ),
        child: frames.isEmpty
            ? Text('no frames', style: RadarTypography.monoLabel)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final frame in frames) _RadarStackFrameRow(frame),
                ],
              ),
      ),
    );
  }
}

class _RadarStackFrameRow extends StatelessWidget {
  const _RadarStackFrameRow(this.frame);

  final RadarStackFrame frame;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Symbol + module take all remaining width and ellipsize (mangled
          // C++/Dart frames are long); the outer Expanded keeps the tag on the
          // right, and the inner Flexibles keep the whole row from overflowing.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    frame.text,
                    style: RadarTypography.monoCode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (frame.module != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      frame.module!,
                      style: RadarTypography.monoLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (frame.tag != null) ...[const SizedBox(width: 8), frame.tag!],
        ],
      ),
    );
  }
}
