import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  group('ClassRootProfile.looksLive', () {
    test('true when liveTree instances are a strict majority', () {
      const profile = ClassRootProfile(
        className: 'MixedState',
        libraryUri: null,
        totalInstances: 3,
        retainedShallowBytes: 48,
        byRoot: {RootKind.liveTree: 2, RootKind.timer: 1},
      );

      expect(profile.looksLive, isTrue);
    });

    test('false when leak-prone instances dominate', () {
      const profile = ClassRootProfile(
        className: 'LeakyState',
        libraryUri: null,
        totalInstances: 3,
        retainedShallowBytes: 48,
        byRoot: {RootKind.liveTree: 1, RootKind.timer: 2},
      );

      expect(profile.looksLive, isFalse);
    });

    test('false on a tie (not a STRICT majority)', () {
      const profile = ClassRootProfile(
        className: 'TiedState',
        libraryUri: null,
        totalInstances: 2,
        retainedShallowBytes: 32,
        byRoot: {RootKind.liveTree: 1, RootKind.timer: 1},
      );

      expect(profile.looksLive, isFalse);
    });

    test('false when there are no instances', () {
      const profile = ClassRootProfile(
        className: 'Empty',
        libraryUri: null,
        totalInstances: 0,
        retainedShallowBytes: 0,
        byRoot: {},
      );

      expect(profile.looksLive, isFalse);
    });
  });

  test('equality and hashCode compare byRoot maps by content', () {
    const a = ClassRootProfile(
      className: 'Foo',
      libraryUri: null,
      totalInstances: 2,
      retainedShallowBytes: 32,
      byRoot: {RootKind.timer: 2},
    );
    const b = ClassRootProfile(
      className: 'Foo',
      libraryUri: null,
      totalInstances: 2,
      retainedShallowBytes: 32,
      byRoot: {RootKind.timer: 2},
    );

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });
}
