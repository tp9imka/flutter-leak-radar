import 'package:flutter/material.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../android/native_profiling_controller.dart';

/// FFI allocation-log view: outstanding native allocations made through the
/// Dart FFI boundary, from the imported [NativeProfilingController.ffiLog]
/// (see `docs/flutter_radar_android_profiling` §4.5). Higher-fidelity
/// sibling of the native still-live lane — every site carries a real
/// `file:line` Dart stack, so unlike the module-only native frames, nothing
/// here is ever tagged with a fidelity caveat: it's all *measured*.
class AndroidFfiScreen extends StatelessWidget {
  const AndroidFfiScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final log = controller.ffiLog;
        return log == null ? const _EmptyState() : _ReadyState(log: log);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Import an ffi allocation log (Capture / import) to see '
          'fix-grade ffi leaks with Dart stacks.',
          style: RadarTypography.caption,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({required this.log});

  final FfiAllocationLog log;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(log: log),
        const _ColumnHeader(),
        const Divider(height: 1, color: RadarColors.hairline08),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: log.sites.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: RadarColors.hairline08),
            itemBuilder: (context, i) => _SiteRow(site: log.sites[i]),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.log});

  final FfiAllocationLog log;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Text('ffi allocations', style: RadarTypography.appBarTitle),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '${log.sites.length} sites · fix-grade, measured',
              style: RadarTypography.monoLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          RadarMetricTile(
            label: 'still-live',
            value: fmtBytes(log.totalStillLiveBytes),
          ),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: RadarColors.bgTableHeader),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text('site ▸ file', style: RadarTypography.monoLabel),
            ),
            SizedBox(
              width: 96,
              child: Text(
                'still-live',
                style: RadarTypography.monoLabel,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                'blocks',
                style: RadarTypography.monoLabel,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ffi allocation site: its header row (site · file · still-live ·
/// blocks) expands, via [RadarExpandableRow], to the Dart stack that
/// allocated it — every frame already `'Function  file.dart:line'`, so no
/// module or fidelity tag is needed (all measured, per §4.5).
class _SiteRow extends StatelessWidget {
  const _SiteRow({required this.site});

  final FfiAllocationSite site;

  @override
  Widget build(BuildContext context) {
    return RadarExpandableRow(
      header: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  site.site,
                  style: RadarTypography.monoBody.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                if (site.file.isNotEmpty)
                  Text(
                    site.file,
                    style: RadarTypography.monoLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              fmtBytes(site.stillLiveBytes),
              style: RadarTypography.monoNumber.copyWith(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              '${site.stillLiveBlocks}',
              style: RadarTypography.monoNumber.copyWith(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 22, bottom: 8),
        child: RadarStackList(
          frames: [
            for (final line in site.dartStack) RadarStackFrame(text: line),
          ],
        ),
      ),
    );
  }
}
