import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

/// Coarse grouping of a [RootKind] used to visually separate live objects
/// (retained by the Flutter UI tree) from leak-prone ones.
enum RootBucket { live, leakProne, other }

RootBucket rootBucket(RootKind kind) {
  if (kind == RootKind.liveTree) return RootBucket.live;
  return kind.isLeakProne ? RootBucket.leakProne : RootBucket.other;
}

extension RootBucketUi on RootBucket {
  Color get color => switch (this) {
    RootBucket.live => RadarColors.accent,
    RootBucket.leakProne => RadarColors.critical,
    RootBucket.other => RadarColors.text40,
  };

  String get label => switch (this) {
    RootBucket.live => 'Live tree',
    RootBucket.leakProne => 'Leak-prone roots',
    RootBucket.other => 'Other roots',
  };
}

/// A small filled dot in the bucket colour for [kind].
class RootDot extends StatelessWidget {
  const RootDot({super.key, required this.kind, this.size = 8});

  final RootKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: rootBucket(kind).color,
        shape: BoxShape.circle,
      ),
    );
  }
}
