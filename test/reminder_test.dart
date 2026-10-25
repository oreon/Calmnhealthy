// Reminders (v2.3.0): pure scheduling-plan logic — stable
// task-id → notification-id assignment and the specs built from a
// plan — plus the guarded service driven by fake backends, so no
// test ever touches the real notifications plugin.

import 'package:calm_n_healthy/main.dart';
import 'package:calm_n_healthy/reminder_service.dart';
import 'package:calm_n_healthy/today_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeReminderBackend implements ReminderBackend {
  int initializeCalls = 0;
  int permissionCalls = 0;
  final List<ReminderSpec> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    return true;
  }

  @override
  Future<void> scheduleDaily(ReminderSpec spec) async {
    scheduled.add(spec);
  }

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
  }
}

class ThrowingReminderBackend implements ReminderBackend {
  @override
  Future<void> initialize() async => throw StateError('plugin exploded');

  @override
  Future<bool> requestPermission() async => throw StateError('nope');

  @override
  Future<void> scheduleDaily(ReminderSpec spec) async =>
      throw StateError('nope');

  @override
  Future<void> cancel(int notificationId) async => throw StateError('nope');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('assignReminderIds', () {
    test('allocates distinct ids starting at 1 for a fresh plan', () {
      final map = assignReminderIds(seedTasks, const {});
      expect(map.length, seedTasks.length);
      expect(map.values.toSet().length, seedTasks.length);
      expect(map.values.every((id) => id >= 1), isTrue);
      expect(map['water'], 1); // First plan task, first id.
    });

    test('is stable: reassigning the same plan changes nothing', () {
      final first = assignReminderIds(seedTasks, const {});
      final second = assignReminderIds(seedTasks, first);
      expect(second, first);
    });

    test('a new task gets an id above the max; others keep theirs', () {
      final first = assignReminderIds(seedTasks, const {});
      const extra = PlanTask(id: 'stretch', name: 'Stretch', time: '21:00');
      final grown = assignReminderIds([...seedTasks, extra], first);
      for (final task in seedTasks) {
        expect(grown[task.id], first[task.id]);
      }
      final highest = first.values.reduce((a, b) => a > b ? a : b);
      expect(grown['stretch'], greaterThan(highest));
    });

    test('a removed task keeps its entry; its id is never reused', () {
      final first = assignReminderIds(seedTasks, const {});
      final waterId = first['water']!;
      final withoutWater = [
        for (final task in seedTasks)
          if (task.id != 'water') task,
      ];
      const replacement = PlanTask(
        id: 'lemon-water',
        name: 'Lemon water',
        time: '06:05',
      );
      final next = assignReminderIds([...withoutWater, replacement], first);
      expect(next['water'], waterId); // Entry retained.
      expect(next['lemon-water'], isNot(waterId)); // Never reused.
    });
  });

  group('buildReminderSpecs', () {
    test('one spec per task, ordered by time, fields from the task', () {
      final map = assignReminderIds(seedTasks, const {});
      final specs = buildReminderSpecs(seedTasks, map);
      expect(specs.length, seedTasks.length);
      expect(specs.first.taskId, 'water');
      expect(specs.first.hour, 6);
      expect(specs.first.minute, 0);
      expect(specs.last.taskId, 'phone-off');
      expect(specs.last.hour, 20);
      for (final spec in specs) {
        expect(spec.notificationId, map[spec.taskId]);
        final task = seedTasks.firstWhere((t) => t.id == spec.taskId);
        expect(spec.body, task.name);
        expect(spec.hour, task.hour);
        expect(spec.minute, task.minute);
      }
    });

    test('rename and reschedule keep the notification id', () {
      final map = assignReminderIds(seedTasks, const {});
      final before = buildReminderSpecs(seedTasks, map)
          .firstWhere((s) => s.taskId == 'journal');
      final edited = rescheduleTask(
        [
          for (final task in seedTasks)
            if (task.id == 'journal') task.copyWith(name: 'Evening pages'),
        ],
        'journal',
        '21:15',
      );
      final after = buildReminderSpecs(edited, map)
          .firstWhere((s) => s.taskId == 'journal');
      expect(after.notificationId, before.notificationId);
      expect(after.body, 'Evening pages');
      expect(after.hour, 21);
      expect(after.minute, 15);
    });
  });

  group('id map encoding', () {
    test('round-trips', () {
      final map = {'water': 1, 'journal': 12};
      expect(decodeReminderIds(encodeReminderIds(map)), map);
    });

    test('corrupt data decodes to empty or partial, never throws', () {
      expect(decodeReminderIds(null), isEmpty);
      expect(decodeReminderIds('not json'), isEmpty);
      expect(decodeReminderIds('[1,2]'), isEmpty);
      expect(
        decodeReminderIds('{"a": 3, "b": "x", "c": 2.5}'),
        {'a': 3},
      );
    });
  });

  group('ReminderService with a fake backend', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('rescheduleAll schedules the plan and persists stable ids',
        () async {
      final backend = FakeReminderBackend();
      final service = ReminderService(backend: backend);

      await service.rescheduleAll(seedTasks);
      expect(backend.scheduled.length, seedTasks.length);
      expect(backend.permissionCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      final stored = decodeReminderIds(prefs.getString(reminderIdsKey));
      expect(stored.length, seedTasks.length);
      for (final spec in backend.scheduled) {
        expect(spec.notificationId, stored[spec.taskId]);
      }

      // A second reschedule cancels the old ids and reuses them —
      // no churn, and permission is not requested again.
      backend.scheduled.clear();
      backend.cancelled.clear();
      await service.rescheduleAll(seedTasks);
      expect(backend.cancelled.toSet(), stored.values.toSet());
      expect(backend.scheduled.length, seedTasks.length);
      for (final spec in backend.scheduled) {
        expect(spec.notificationId, stored[spec.taskId]);
      }
      expect(backend.permissionCalls, 1);
    });

    test('setEnabled(false) cancels everything and blocks reschedules',
        () async {
      final backend = FakeReminderBackend();
      final service = ReminderService(backend: backend);

      await service.rescheduleAll(seedTasks);
      backend.scheduled.clear();
      backend.cancelled.clear();

      await service.setEnabled(false);
      expect(await service.isEnabled(), isFalse);
      expect(backend.cancelled.length, seedTasks.length);

      await service.rescheduleAll(seedTasks);
      expect(backend.scheduled, isEmpty); // Still off: no scheduling.
    });

    test('a throwing backend is swallowed whole', () async {
      final service = ReminderService(backend: ThrowingReminderBackend());
      // None of these may throw, however broken the plugin is.
      await service.rescheduleAll(seedTasks);
      await service.syncReminders();
      await service.cancelAll();
      await service.setEnabled(true);
      await service.setEnabled(false);
      // Enabled state stayed consistent (prefs-driven) throughout.
      expect(await service.isEnabled(), isFalse);
    });
  });

  testWidgets('Today bell toggles reminders off and on', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'cnh.onboarded': true});

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();

    // Default state: reminders on.
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(remindersEnabledKey), isFalse);

    await tester.tap(find.byIcon(Icons.notifications_off_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(prefs.getBool(remindersEnabledKey), isTrue);
  });
}
