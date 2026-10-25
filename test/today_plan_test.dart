import 'package:calm_n_healthy/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('section grouping boundaries', () {
    test('11:59 is Morning', () {
      expect(sectionForTime(11, 59), PlanSection.morning);
    });

    test('12:00 is Afternoon', () {
      expect(sectionForTime(12, 0), PlanSection.afternoon);
    });

    test('17:59 is Afternoon', () {
      expect(sectionForTime(17, 59), PlanSection.afternoon);
    });

    test('18:00 is Evening', () {
      expect(sectionForTime(18, 0), PlanSection.evening);
    });
  });

  group('seed plan', () {
    test('has exactly 13 tasks', () {
      expect(seedTasks, hasLength(13));
    });

    test('phone-off is last, at 20:00', () {
      final last = seedTasks.last;
      expect(last.name, 'Turn phone off');
      expect(last.time, '20:00');
    });

    test('grouping splits the seed plan across the three sections', () {
      final grouped = groupBySection(seedTasks);
      expect(grouped[PlanSection.morning], hasLength(5));
      expect(grouped[PlanSection.afternoon], hasLength(4));
      expect(grouped[PlanSection.evening], hasLength(4));
      expect(grouped[PlanSection.evening]!.last.name, 'Turn phone off');
    });
  });

  group('points toggling', () {
    test('checking awards +10 once; unchecking removes it', () {
      final checked = toggleTask(
        completedIds: const {},
        lifetimePoints: 0,
        taskId: 'water',
        complete: true,
      );
      expect(checked.completedIds, {'water'});
      expect(checked.lifetimePoints, 10);
      expect(checked.dayPoints, 10);

      final rechecked = toggleTask(
        completedIds: checked.completedIds,
        lifetimePoints: checked.lifetimePoints,
        taskId: 'water',
        complete: true,
      );
      expect(rechecked.lifetimePoints, 10);

      final unchecked = toggleTask(
        completedIds: checked.completedIds,
        lifetimePoints: checked.lifetimePoints,
        taskId: 'water',
        complete: false,
      );
      expect(unchecked.completedIds, isEmpty);
      expect(unchecked.lifetimePoints, 0);
      expect(unchecked.dayPoints, 0);
    });
  });

  group('overdue', () {
    const task = PlanTask(id: 'water', name: 'Water', time: '06:00');

    test('past, incomplete task is overdue', () {
      expect(
        isOverdue(task, nowMinutesOfDay: 7 * 60, completed: false),
        isTrue,
      );
    });

    test('completed or not-yet-due tasks are not overdue', () {
      expect(
        isOverdue(task, nowMinutesOfDay: 7 * 60, completed: true),
        isFalse,
      );
      expect(
        isOverdue(task, nowMinutesOfDay: 5 * 60, completed: false),
        isFalse,
      );
    });
  });
}
