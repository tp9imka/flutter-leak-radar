import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import 'first_run_guide_controller.dart';
import 'guide_copy.dart';

TextStyle _modalTitleStyle() => radarDisplayStyle(
  fontSize: 22,
  fontWeight: FontWeight.w600,
  color: RadarColors.text100,
  height: 1.2,
);

TextStyle _calloutTitleStyle() => radarDisplayStyle(
  fontSize: 17,
  fontWeight: FontWeight.w600,
  color: RadarColors.text100,
  height: 1.25,
);

/// Width-capped, centered wrapper for the welcome/finish modals: spec
/// §6, `min(460px, 86%)`.
class _CenteredCard extends StatelessWidget {
  const _CenteredCard({required this.child});

  final Widget child;

  static const double _maxWidth = 460;

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width * 0.86;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: math.min(_maxWidth, available)),
      child: child,
    );
  }
}

/// Shared panel chrome for the welcome/finish modals: surface fill,
/// hairline border, and the ✕ close affordance in the top-right corner.
class _ModalShell extends StatelessWidget {
  const _ModalShell({required this.onClose, required this.child});

  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RadarColors.hairline10),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              top: -8,
              right: -8,
              child: _CloseButton(onPressed: onClose),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  static const double _size = 26;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Close',
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: _size, height: _size),
      icon: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: RadarColors.iconButtonBg,
          border: Border.all(color: RadarColors.hairline12),
        ),
        child: const Icon(Icons.close, size: 14, color: RadarColors.text60),
      ),
    );
  }
}

class _MotifBadge extends StatelessWidget {
  const _MotifBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: RadarColors.accentSubtle,
        border: Border.all(color: RadarColors.accent.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: RadarColors.accent, size: 22),
    );
  }
}

/// The step-0 modal: the tour's entry point (spec §3, "Welcome").
class GuideWelcomeCard extends StatelessWidget {
  const GuideWelcomeCard({
    super.key,
    required this.onSkip,
    required this.onStart,
  });

  final VoidCallback onSkip;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _CenteredCard(
        child: _ModalShell(
          onClose: onSkip,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _MotifBadge(icon: Icons.radar),
              const SizedBox(height: 16),
              Text('Welcome to Radar Desktop', style: _modalTitleStyle()),
              const SizedBox(height: 10),
              Text(
                'Analyze Flutter memory, performance, stability, and '
                "native-heap data — from offline captures or a live app. "
                "Here's a quick tour of what's here. Takes about a "
                'minute.',
                style: RadarTypography.body,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _SecondaryButton(label: 'Skip for now', onPressed: onSkip),
                  _PrimaryButton(label: 'Take the tour →', onPressed: onStart),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Esc to skip · ← → to navigate · shown once.',
                style: RadarTypography.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The step-6 modal: the tour's exit point (spec §3, "Finish").
class GuideFinishCard extends StatelessWidget {
  const GuideFinishCard({
    super.key,
    required this.onSkip,
    required this.onBack,
    required this.onDone,
  });

  final VoidCallback onSkip;
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _CenteredCard(
        child: _ModalShell(
          onClose: onSkip,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _MotifBadge(icon: Icons.check_rounded),
              const SizedBox(height: 16),
              Text("You're set.", style: _modalTitleStyle()),
              const SizedBox(height: 10),
              Text(
                'Start by importing a heap dump or a .pftrace — button or '
                'drag-and-drop anywhere. Connect to a running app to '
                'unlock Performance & Stability.',
                style: RadarTypography.body,
              ),
              const SizedBox(height: 14),
              const _TipBox(
                text:
                    'every error has a Copy action, and you can reopen '
                    'this tour any time from the ? in the title bar.',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _SecondaryButton(label: 'Back', onPressed: onBack),
                  _PrimaryButton(label: 'Done', onPressed: onDone),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipBox extends StatelessWidget {
  const _TipBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.accentSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RadarColors.hairline10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.lightbulb_outline,
              size: 14,
              color: RadarColors.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: RadarTypography.body.copyWith(color: RadarColors.text80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A spotlight callout's note, tinted and iconed per [tone]: accent for
/// a positive/informational note (step 1), warning for a locked-feature
/// or missing-tool note (steps 3 and 5). See spec §3.
class _SpotlightNote extends StatelessWidget {
  const _SpotlightNote({required this.text, required this.tone});

  final String text;
  final NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      NoteTone.accent => RadarColors.accent,
      NoteTone.warning => RadarColors.warning,
    };
    final icon = switch (tone) {
      NoteTone.accent => Icons.bolt,
      NoteTone.warning => Icons.warning_amber_rounded,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: RadarTypography.caption.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= FirstRunGuideController.lastSpotlight; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          _ProgressDot(active: i == current),
        ],
      ],
    );
  }
}

class _ProgressDot extends StatelessWidget {
  const _ProgressDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 14 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? RadarColors.accent : RadarColors.text15,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// A step-1..5 spotlight's callout card: kicker, "N / 5" counter, title,
/// body, an optional accent- or warning-toned note, progress dots, and
/// the Skip/Back/Next (or Finish) actions.
class GuideSpotlightCallout extends StatelessWidget {
  const GuideSpotlightCallout({
    super.key,
    required this.copy,
    required this.step,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
  });

  final GuideSpotlightCopy copy;
  final int step;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isLastSpotlight = step == FirstRunGuideController.lastSpotlight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RadarColors.hairline10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    copy.kicker,
                    style: RadarTypography.monoLabel.copyWith(
                      color: RadarColors.accent,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  '$step / ${FirstRunGuideController.lastSpotlight}',
                  style: RadarTypography.monoLabel,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(copy.title, style: _calloutTitleStyle()),
            const SizedBox(height: 8),
            Text(copy.body, style: RadarTypography.body),
            if (copy.note case final note?) ...[
              const SizedBox(height: 12),
              _SpotlightNote(text: note, tone: copy.noteTone),
            ],
            const SizedBox(height: 14),
            _ProgressDots(current: step),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _TextActionButton(label: 'Skip', onPressed: onSkip),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SecondaryButton(label: 'Back', onPressed: onBack),
                    _PrimaryButton(
                      label: isLastSpotlight ? 'Finish' : 'Next',
                      onPressed: onNext,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: RadarDensity.inputRadius),
        textStyle: RadarTypography.body.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: RadarColors.text60,
        side: const BorderSide(color: RadarColors.hairline12),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: RadarDensity.inputRadius),
        textStyle: RadarTypography.body,
      ),
      child: Text(label),
    );
  }
}

class _TextActionButton extends StatelessWidget {
  const _TextActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: RadarColors.text50,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: RadarTypography.body,
      ),
      child: Text(label),
    );
  }
}
