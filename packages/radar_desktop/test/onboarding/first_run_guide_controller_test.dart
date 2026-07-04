import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/onboarding/first_run_guide_controller.dart';

/// In-memory [FirstRunStore] fake — no real fs/path_provider.
class _FakeFirstRunStore implements FirstRunStore {
  bool seen = false;
  int markSeenCount = 0;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async {
    seen = true;
    markSeenCount++;
  }
}

void main() {
  group('FirstRunGuideController.load', () {
    test('opens at the welcome step when unseen', () async {
      final controller = FirstRunGuideController(store: _FakeFirstRunStore());

      await controller.load();

      expect(controller.open, isTrue);
      expect(controller.step, 0);
      expect(controller.seen, isFalse);
    });

    test('stays closed when already seen', () async {
      final store = _FakeFirstRunStore()..seen = true;
      final controller = FirstRunGuideController(store: store);

      await controller.load();

      expect(controller.open, isFalse);
      expect(controller.seen, isTrue);
    });
  });

  group('FirstRunGuideController.next', () {
    test('walks every step from welcome to finish, then completes', () async {
      final store = _FakeFirstRunStore();
      final controller = FirstRunGuideController(store: store);
      await controller.load();

      for (var expected = 1; expected <= 6; expected++) {
        controller.next();
        expect(controller.step, expected);
      }
      expect(controller.open, isTrue);
      expect(controller.step, FirstRunGuideController.lastSpotlight + 1);

      controller.next();

      expect(controller.open, isFalse);
      expect(controller.seen, isTrue);
      expect(store.markSeenCount, 1);
    });
  });

  group('FirstRunGuideController.back', () {
    test('steps back down and floors at the welcome step', () async {
      final controller = FirstRunGuideController(store: _FakeFirstRunStore());
      await controller.load();
      for (var i = 0; i < 6; i++) {
        controller.next();
      }
      expect(controller.step, 6);

      for (var expected = 5; expected >= 0; expected--) {
        controller.back();
        expect(controller.step, expected);
      }

      controller.back();

      expect(controller.step, 0);
    });
  });

  group('FirstRunGuideController.skip', () {
    test('closes the guide and marks it seen from any step', () async {
      final store = _FakeFirstRunStore();
      final controller = FirstRunGuideController(store: store);
      await controller.load();
      controller.next();
      controller.next();

      controller.skip();

      expect(controller.open, isFalse);
      expect(controller.seen, isTrue);
      expect(store.markSeenCount, 1);
    });
  });

  group('FirstRunGuideController.reopen', () {
    test('re-opens at the welcome step without changing seen', () async {
      final store = _FakeFirstRunStore();
      final controller = FirstRunGuideController(store: store);
      await controller.load();
      controller.skip();
      expect(controller.seen, isTrue);
      expect(store.markSeenCount, 1);

      controller.reopen();

      expect(controller.open, isTrue);
      expect(controller.step, 0);
      expect(controller.seen, isTrue);
      expect(store.markSeenCount, 1);
    });
  });

  group('FirstRunGuideController.dispose', () {
    test('does not notify listeners after dispose', () async {
      final controller = FirstRunGuideController(store: _FakeFirstRunStore());
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.dispose();
      controller.skip();

      expect(notified, 0);
    });
  });
}
