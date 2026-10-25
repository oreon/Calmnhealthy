// Configure Your Day: plan template model, library and persistence.

import 'package:calm_n_healthy/breathing.dart';
import 'package:calm_n_healthy/plan_library.dart';
import 'package:calm_n_healthy/plan_store.dart';
import 'package:calm_n_healthy/practice_catalog.dart';
import 'package:calm_n_healthy/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('seed task practice links', () {
    PlanTask byId(String id) => seedTasks.firstWhere((t) => t.id == id);

    test('seed keeps exactly the 13 spec ids', () {
      expect(seedTasks.map((t) => t.id), [
        'water',
        'meditation',
        'strength',
        'yoga',
        'mindful-breakfast',
        'yoga-nidra',
        'mindful-lunch',
        'box-breathing',
        'fluid-reminder',
        'evening-meditation',
        'wind-down',
        'journal',
        'phone-off',
      ]);
    });

    test('meditation, strength and yoga link to their practices', () {
      expect(byId('meditation').kind, PlanTaskKind.practice);
      expect(byId('meditation').practiceId, 'meditation-20');
      expect(byId('evening-meditation').kind, PlanTaskKind.practice);
      expect(byId('evening-meditation').practiceId, 'meditation-20');
      expect(byId('strength').kind, PlanTaskKind.practice);
      expect(byId('strength').practiceId, strengthPracticeLink);
      expect(byId('yoga').kind, PlanTaskKind.practice);
      expect(byId('yoga').practiceId, 'yoga');
    });

    test('yoga nidra stays simple; box breathing links to its pattern', () {
      expect(byId('yoga-nidra').kind, PlanTaskKind.simple);
      expect(byId('yoga-nidra').practiceId, isNull);
      // Since v2.4.0 box breathing has a real session (the pacer),
      // so the seed task is a practice row like the others.
      expect(byId('box-breathing').kind, PlanTaskKind.practice);
      expect(byId('box-breathing').practiceId, 'box-breathing');
    });

    test('every seeded practice link resolves to a real practice', () {
      for (final task in seedTasks.where(
        (t) => t.kind == PlanTaskKind.practice,
      )) {
        expect(
          task.practiceId == strengthPracticeLink ||
              practiceById(task.practiceId!) != null ||
              breathingPatternById(task.practiceId!) != null,
          isTrue,
          reason: '${task.id} links to ${task.practiceId}',
        );
      }
    });
  });

  group('library', () {
    test('covers all four categories with unique ids', () {
      final ids = planLibrary.map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final category in PlanCategory.values) {
        expect(libraryEntriesFor(category), isNotEmpty, reason: '$category');
      }
    });

    test('meditation presets 5/10/20/30/45 are practice entries', () {
      for (final minutes in [5, 10, 20, 30, 45]) {
        final entry = planLibraryEntryById('meditation-$minutes');
        expect(entry, isNotNull, reason: 'meditation-$minutes');
        expect(entry!.kind, PlanTaskKind.practice);
        expect(entry.practiceId, 'meditation-$minutes');
        expect(practiceById(entry.practiceId!), isNotNull);
      }
    });

    test('habit entries are simple and match the seed defaults', () {
      for (final entry in libraryEntriesFor(PlanCategory.habits)) {
        expect(entry.kind, PlanTaskKind.simple, reason: entry.id);
        expect(entry.practiceId, isNull, reason: entry.id);
      }
      expect(planLibraryEntryById('water')!.defaultTime, '06:00');
      expect(planLibraryEntryById('phone-off')!.defaultTime, '20:00');
    });
  });

  group('plan template operations', () {
    test('add from library appends at the default time', () {
      final pranayama = planLibraryEntryById('pranayama')!.toTask();
      final plan = tryAddTask(List.of(seedTasks), pranayama);
      expect(plan, isNotNull);
      expect(plan!.last.id, 'pranayama');
      expect(plan.last.time, '06:45');
      expect(plan.last.kind, PlanTaskKind.practice);
      // Display order sorts it into the morning by time.
      expect(
        sortedPlan(plan).map((t) => t.id),
        containsAllInOrder(['water', 'meditation', 'pranayama', 'strength']),
      );
    });

    test('adding an item already in the plan is rejected', () {
      final strength = planLibraryEntryById('strength')!.toTask();
      expect(tryAddTask(List.of(seedTasks), strength), isNull);
      final water = planLibraryEntryById('water')!.toTask();
      expect(tryAddTask(List.of(seedTasks), water), isNull);
    });

    test('delete removes only that task', () {
      final plan = removeTask(List.of(seedTasks), 'journal');
      expect(plan, hasLength(12));
      expect(plan.any((t) => t.id == 'journal'), isFalse);
      expect(plan.last.id, 'phone-off');
    });

    test('reschedule changes the time and the section grouping', () {
      final plan = rescheduleTask(List.of(seedTasks), 'water', '19:05');
      final water = plan.firstWhere((t) => t.id == 'water');
      expect(water.time, '19:05');
      expect(sectionOf(water), PlanSection.evening);
      final grouped = groupBySection(sortedPlan(plan));
      expect(
        grouped[PlanSection.morning]!.any((t) => t.id == 'water'),
        isFalse,
      );
      // In the Evening section it sorts by time: after the 19:00
      // Evening meditation, before Wind down at 19:30.
      expect(grouped[PlanSection.evening]!.map((t) => t.id), [
        'evening-meditation',
        'water',
        'wind-down',
        'journal',
        'phone-off',
      ]);
      // Everything else keeps its section.
      expect(grouped[PlanSection.morning], hasLength(4));
    });

    test('display order is by time, manual order breaking ties', () {
      const a = PlanTask(id: 'a', name: 'A', time: '07:00');
      const b = PlanTask(id: 'b', name: 'B', time: '07:00');
      const c = PlanTask(id: 'c', name: 'C', time: '06:00');
      expect(sortedPlan([a, b, c]).map((t) => t.id), ['c', 'a', 'b']);
      expect(sortedPlan([b, a, c]).map((t) => t.id), ['c', 'b', 'a']);
      // The seed is already in display order.
      expect(sortedPlan(seedTasks), seedTasks);
    });

    test('template JSON round-trips tasks incl. kind and practiceId', () {
      const custom = [
        PlanTask(
          id: 'meditation-10',
          name: 'Meditation 10 min',
          time: '06:10',
          kind: PlanTaskKind.practice,
          practiceId: 'meditation-10',
        ),
        PlanTask(id: 'water', name: 'Water', time: '06:00'),
        PlanTask(
          id: 'strength',
          name: 'Strength',
          time: '07:00',
          kind: PlanTaskKind.practice,
          practiceId: strengthPracticeLink,
        ),
      ];
      expect(decodePlanTemplate(encodePlanTemplate(custom)), custom);
      expect(decodePlanTemplate('not json'), isNull);
      expect(decodePlanTemplate('{"nope":true}'), isNull);
      expect(decodePlanTemplate('[{"id":"x"}]'), isNull);
    });

    test('a kept task retains its same-day completion after edits', () {
      // Edit the plan around: reschedule water, delete journal,
      // add pranayama. Completion is keyed by task id and lives
      // outside the template, so water's check survives untouched.
      var plan = rescheduleTask(List.of(seedTasks), 'water', '06:30');
      plan = removeTask(plan, 'journal');
      plan = tryAddTask(plan, planLibraryEntryById('pranayama')!.toTask())!;
      expect(plan.any((t) => t.id == 'water' && t.time == '06:30'), isTrue);

      const completed = {'water'};
      // Re-checking the kept, already-done task awards nothing twice…
      final rechecked = toggleTask(
        completedIds: completed,
        lifetimePoints: 10,
        taskId: 'water',
        complete: true,
      );
      expect(rechecked.lifetimePoints, 10);
      expect(rechecked.completedIds, {'water'});
      // …and unchecking still removes exactly its award.
      final unchecked = toggleTask(
        completedIds: completed,
        lifetimePoints: 10,
        taskId: 'water',
        complete: false,
      );
      expect(unchecked.completedIds, isEmpty);
      expect(unchecked.lifetimePoints, 0);
    });
  });

  group('PlanStore persistence', () {
    test('no template saved → the seed plan', () async {
      SharedPreferences.setMockInitialValues({});
      final plan = await PlanStore.loadPlan();
      expect(plan, hasLength(13));
      expect(plan.map((t) => t.id), seedTasks.map((t) => t.id));
    });

    test('corrupt template → the seed plan', () async {
      SharedPreferences.setMockInitialValues({
        PlanStore.templateKey: 'not json',
      });
      final plan = await PlanStore.loadPlan();
      expect(plan, hasLength(13));
      expect(plan.first.id, 'water');
    });

    test('template save/load round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      const custom = [
        PlanTask(
          id: 'meditation-10',
          name: 'Meditation 10 min',
          time: '06:10',
          kind: PlanTaskKind.practice,
          practiceId: 'meditation-10',
        ),
        PlanTask(id: 'water', name: 'Water', time: '06:00'),
      ];
      await PlanStore.savePlan(custom);
      expect(await PlanStore.loadPlan(), custom);
    });

    test('reset restores the seed and clears ONLY the template key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cnh.lifetime_points', 50);
      await prefs.setStringList('cnh.done.2026-10-25', ['water']);
      await PlanStore.savePlan([
        const PlanTask(id: 'x', name: 'X', time: '07:00'),
      ]);

      await PlanStore.resetToDefaults();

      expect(prefs.getString(PlanStore.templateKey), isNull);
      expect(prefs.getInt('cnh.lifetime_points'), 50);
      expect(prefs.getStringList('cnh.done.2026-10-25'), ['water']);
      final plan = await PlanStore.loadPlan();
      expect(plan.map((t) => t.id), seedTasks.map((t) => t.id));
    });
  });
}
