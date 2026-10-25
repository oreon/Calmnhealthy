/// Pure-Dart model for the Today daily plan: the seed task list,
/// section grouping, points rules and per-day completion math.
///
/// No Flutter imports on purpose — everything here is unit-testable
/// without widgets.
library;

/// Points awarded for completing one plan task (once per task per day).
const int pointsPerTask = 10;

/// One task in the daily plan.
class PlanTask {
  final String id;
  final String name;

  /// Scheduled time of day, 'HH:mm' in 24-hour form.
  final String time;

  const PlanTask({required this.id, required this.name, required this.time});

  int get hour => int.parse(time.substring(0, 2));
  int get minute => int.parse(time.substring(3, 5));

  /// Minutes since midnight, for ordering and section math.
  int get minutesOfDay => hour * 60 + minute;
}

/// The seeded daily plan: 13 tasks, phone-off last at 20:00.
const List<PlanTask> seedTasks = [
  PlanTask(id: 'water', name: 'Water', time: '06:00'),
  PlanTask(id: 'meditation', name: 'Meditation', time: '06:20'),
  PlanTask(id: 'strength', name: 'Strength', time: '07:00'),
  PlanTask(id: 'yoga', name: 'Yoga', time: '07:30'),
  PlanTask(id: 'mindful-breakfast', name: 'Mindful breakfast', time: '08:00'),
  PlanTask(id: 'yoga-nidra', name: 'Yoga Nidra', time: '12:00'),
  PlanTask(id: 'mindful-lunch', name: 'Mindful lunch', time: '13:30'),
  PlanTask(id: 'box-breathing', name: 'Box breathing', time: '14:00'),
  PlanTask(id: 'fluid-reminder', name: 'Fluid reminder', time: '15:00'),
  PlanTask(id: 'evening-meditation', name: 'Evening meditation', time: '19:00'),
  PlanTask(id: 'wind-down', name: 'Wind down', time: '19:30'),
  PlanTask(id: 'journal', name: 'Journal', time: '19:45'),
  PlanTask(id: 'phone-off', name: 'Turn phone off', time: '20:00'),
];

/// Day sections: Morning before 12:00, Afternoon 12:00–17:59,
/// Evening from 18:00.
enum PlanSection { morning, afternoon, evening }

extension PlanSectionLabel on PlanSection {
  String get label => switch (this) {
        PlanSection.morning => 'Morning',
        PlanSection.afternoon => 'Afternoon',
        PlanSection.evening => 'Evening',
      };
}

/// Which section a moment of the day (minutes since midnight) is in.
PlanSection sectionForMinutes(int minutesOfDay) {
  if (minutesOfDay < 12 * 60) return PlanSection.morning;
  if (minutesOfDay < 18 * 60) return PlanSection.afternoon;
  return PlanSection.evening;
}

/// Which section a wall-clock time is in.
PlanSection sectionForTime(int hour, int minute) =>
    sectionForMinutes(hour * 60 + minute);

/// Which section a task belongs to, by its scheduled time.
PlanSection sectionOf(PlanTask task) => sectionForMinutes(task.minutesOfDay);

/// Groups tasks by section, preserving the input order within each
/// section and returning all three sections (possibly empty) in
/// Morning/Afternoon/Evening order.
Map<PlanSection, List<PlanTask>> groupBySection(List<PlanTask> tasks) {
  final grouped = <PlanSection, List<PlanTask>>{
    for (final section in PlanSection.values) section: <PlanTask>[],
  };
  for (final task in tasks) {
    grouped[sectionOf(task)]!.add(task);
  }
  return grouped;
}

/// A task is overdue when it is not completed and its scheduled time
/// today has already passed.
bool isOverdue(
  PlanTask task, {
  required int nowMinutesOfDay,
  required bool completed,
}) =>
    !completed && task.minutesOfDay < nowMinutesOfDay;

/// The result of checking or unchecking one task for a day: the new
/// set of completed task ids and the new lifetime points total.
class ToggleOutcome {
  final Set<String> completedIds;
  final int lifetimePoints;

  const ToggleOutcome(this.completedIds, this.lifetimePoints);

  /// Points earned so far today (one award per completed task).
  int get dayPoints => completedIds.length * pointsPerTask;
}

/// Applies a check/uncheck to a day's completion set and the lifetime
/// points total. Checking a task awards [pointsPerTask] once;
/// unchecking removes that award. Toggling to the state the task is
/// already in changes nothing.
ToggleOutcome toggleTask({
  required Set<String> completedIds,
  required int lifetimePoints,
  required String taskId,
  required bool complete,
}) {
  final next = Set<String>.of(completedIds);
  var lifetime = lifetimePoints;
  if (complete && !next.contains(taskId)) {
    next.add(taskId);
    lifetime += pointsPerTask;
  } else if (!complete && next.contains(taskId)) {
    next.remove(taskId);
    lifetime -= pointsPerTask;
    if (lifetime < 0) lifetime = 0;
  }
  return ToggleOutcome(next, lifetime);
}
