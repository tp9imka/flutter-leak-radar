import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

/// Shown when `ext.perf_radar.snapshot` is not registered in the
/// connected app — PerfRadar has not been initialised.
class PerfRadarNotDetectedView extends StatelessWidget {
  const PerfRadarNotDetectedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.radar, size: 40, color: RadarColors.text25),
          const SizedBox(height: 16),
          Text(
            'PerfRadar not detected in the connected app',
            style: RadarTypography.body.copyWith(color: RadarColors.text60),
          ),
          const SizedBox(height: 8),
          Text(
            'Add PerfRadar.init() to your app to enable\n'
            'Performance and Stability views.',
            style: RadarTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Loading spinner shown while fetching a snapshot.
class PerfLoadingView extends StatelessWidget {
  const PerfLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              color: RadarColors.accent,
              strokeWidth: 2,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Fetching snapshot…',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12.5,
              color: RadarColors.text40,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state with message and a retry button.
class PerfErrorView extends StatelessWidget {
  const PerfErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 32,
            color: RadarColors.critical,
          ),
          const SizedBox(height: 12),
          Text(
            'Failed to fetch snapshot',
            style: RadarTypography.body.copyWith(color: RadarColors.critical),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: RadarTypography.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _RetryButton(onRetry: onRetry),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: RadarColors.bgInput,
          borderRadius: RadarDensity.inputRadius,
          border: Border.all(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Retry',
            style: RadarTypography.monoLabel.copyWith(
              color: RadarColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// A "Refresh" action button for the toolbar.
class PerfRefreshButton extends StatelessWidget {
  const PerfRefreshButton({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Refresh snapshot',
      child: GestureDetector(
        onTap: onRefresh,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RadarColors.iconButtonBg,
            borderRadius: RadarDensity.iconButtonRadius,
            border: Border.all(
              color: RadarColors.iconButtonBorder,
              width: RadarDensity.hairline,
            ),
          ),
          child: SizedBox(
            width: RadarDensity.iconButtonSize,
            height: RadarDensity.iconButtonSize,
            child: const Icon(
              Icons.refresh,
              size: 15,
              color: RadarColors.text60,
            ),
          ),
        ),
      ),
    );
  }
}

/// A "Reset counters" action button for the Frames toolbar.
///
/// Pairs with [PerfDataController.resetFrames] to zero out accumulated
/// frame statistics on the connected app for a fresh measurement window.
/// When [onReset] is null the button renders disabled — used when there
/// is no live connection to reset.
class PerfResetFramesButton extends StatelessWidget {
  const PerfResetFramesButton({super.key, required this.onReset});

  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final enabled = onReset != null;
    return Tooltip(
      message: 'Reset frame counters',
      child: GestureDetector(
        onTap: onReset,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RadarColors.iconButtonBg,
            borderRadius: RadarDensity.iconButtonRadius,
            border: Border.all(
              color: RadarColors.iconButtonBorder,
              width: RadarDensity.hairline,
            ),
          ),
          child: SizedBox(
            width: RadarDensity.iconButtonSize,
            height: RadarDensity.iconButtonSize,
            child: Icon(
              Icons.restart_alt,
              size: 15,
              color: enabled ? RadarColors.text60 : RadarColors.text25,
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state shown when no rows match the active search / filter.
class PerfEmptyFilterView extends StatelessWidget {
  const PerfEmptyFilterView({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text("No results match '$query'", style: RadarTypography.caption),
    );
  }
}
