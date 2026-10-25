/// Pure-Dart model for the Today daily plan: the seed task list,
/// section grouping, points rules and per-day completion math, plus
/// the user-configured plan template (Configure Your Day): JSON
/// encoding, display ordering and add/remove/reschedule operations.
///
/// No Flutter imports on purpose — everything here is unit-testable
/// without widgets.
library;

import 'dart:convert';

/// Points awarded for completing one plan task (once per task per day).
const int pointsPerTask = 10;

/// What a plan task is: a plain check-off habit, or a guided
/// practice that can be started from its Today row.
enum PlanTaskKind { simple, practice }

/// Special practice link for strength tasks: resolves at tap time
/// to today's Upper/Lower routine via the day-of-year alternation.
const String strengthPracticeLink = 'strength';

/// One task in the daily plan.
class PlanTask {
  /// Stable identifier — per-day completion is keyed by it, so a
  /// task keeps its identity (and its check-off) across plan edits.
  final String id;
  final String name;

  /// Scheduled time of day, 'HH:mm' in 24-hour form.
  final String time;

  /// Whether this is a simple check-off or a startable practice.
  final PlanTaskKind kind;

  /// For [PlanTaskKind.practice] tasks: the practice to open —
  /// a catalog practice id (e.g. 'meditation-20', 'yoga'), or
  /// [strengthPracticeLink] for the alternating strength routine.
  /// Null for simple tasks and for practices without a session yet.
  final String? practiceId;

  const PlanTask({
    required this.id,
    required this.name,
    required this.time,
    this.kind = PlanTaskKind.simple,
    this.practiceId,
  });

  int get hour => int.parse(time.substring(0, 2));
  int get minute => int.parse(time.substring(3, 5));

  /// Minutes since midnight, for ordering and section math.
  int get minutesOfDay => hour * 60 + minute;

  PlanTask copyWith({
    String? name,
    String? time,
    PlanTaskKind? kind,
    String? practiceId,
  }) => PlanTask(
    id: id,
    name: name ?? this.name,
    time: time ?? this.time,
    kind: kind ?? this.kind,
    practiceId: practiceId ?? this.practiceId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'time': time,
    'kind': kind.name,
    if (practiceId != null) 'practiceId': practiceId,
  };

  /// Parses one task, or returns null when the shape is unusable.
  static PlanTask? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final time = json['time'] as String?;
    if (id == null || name == null || time == null) return null;
    final parts = time.split(':');
    if (parts.length != 2 ||
        int.tryParse(parts[0]) == null ||
        int.tryParse(parts[1]) == null) {
      return null;
    }
    return PlanTask(
      id: id,
      name: name,
      time: time,
      kind: (json['kind'] as String?) == 'practice'
          ? PlanTaskKind.practice
          : PlanTaskKind.simple,
      practiceId: json['practiceId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlanTask &&
      other.id == id &&
      other.name == name &&
      other.time == time &&
      other.kind == kind &&
      other.practiceId == practiceId;

  @override
  int get hashCode => Object.hash(id, name, time, kind, practiceId);
}

/// The seeded daily plan: 13 tasks, phone-off last at 20:00.
/// This is the default template — what Configure Your Day resets to.
const List<PlanTask> seedTasks = [
  PlanTask(id: 'water', name: 'Water', time: '06:00'),
  PlanTask(
    id: 'meditation',
    name: 'Meditation',
    time: '06:20',
    kind: PlanTaskKind.practice,
    practiceId: 'meditation-20',
  ),
  PlanTask(
    id: 'strength',
    name: 'Strength',
    time: '07:00',
    kind: PlanTaskKind.practice,
    practiceId: strengthPracticeLink,
  ),
  PlanTask(
    id: 'yoga',
    name: 'Yoga',
    time: '07:30',
    kind: PlanTaskKind.practice,
    practiceId: 'yoga',
  ),
  PlanTask(id: 'mindful-breakfast', name: 'Mindful breakfast', time: '08:00'),
  PlanTask(id: 'yoga-nidra', name: 'Yoga Nidra', time: '12:00'),
  PlanTask(id: 'mindful-lunch', name: 'Mindful lunch', time: '13:30'),
  PlanTask(id: 'box-breathing', name: 'Box breathing', time: '14:00'),
  PlanTask(id: 'fluid-reminder', name: 'Fluid reminder', time: '15:00'),
  PlanTask(
    id: 'evening-meditation',
    name: 'Evening meditation',
    time: '19:00',
    kind: PlanTaskKind.practice,
    practiceId: 'meditation-20',
  ),
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
}) => !completed && task.minutesOfDay < nowMinutesOfDay;

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

// --- Plan template (Configure Your Day) ----------------------------

/// Display order for a plan: by scheduled time; tasks at the same
/// time keep their stored (manual) order — a stable sort, so drag
/// reorder in edit mode decides ties.
List<PlanTask> sortedPlan(List<PlanTask> tasks) {
  final decorated = <(int, PlanTask)>[
    for (var i = 0; i < tasks.length; i++) (i, tasks[i]),
  ];
  decorated.sort((a, b) {
    final byTime = a.$2.minutesOfDay.compareTo(b.$2.minutesOfDay);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final entry in decorated) entry.$2];
}

/// A new plan with [task] appended, or null when a task with the
/// same id is already in the plan (adding is rejected, never doubled).
List<PlanTask>? tryAddTask(List<PlanTask> plan, PlanTask task) {
  if (plan.any((t) => t.id == task.id)) return null;
  return [...plan, task];
}

/// A new plan without the task [id] (unchanged when absent).
List<PlanTask> removeTask(List<PlanTask> plan, String id) => [
  for (final task in plan)
    if (task.id != id) task,
];

/// A new plan with task [id] moved to [newTime] ('HH:mm'); its id,
/// kind and practice link are untouched, so a same-day check-off
/// (keyed by id) survives the reschedule.
List<PlanTask> rescheduleTask(
  List<PlanTask> plan,
  String id,
  String newTime,
) => [
  for (final task in plan) task.id == id ? task.copyWith(time: newTime) : task,
];

/// Serializes a plan template for storage.
String encodePlanTemplate(List<PlanTask> tasks) =>
    jsonEncode([for (final task in tasks) task.toJson()]);

/// Parses a stored plan template, or null when it is unreadable —
/// callers fall back to [seedTasks] rather than showing a broken day.
List<PlanTask>? decodePlanTemplate(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final tasks = <PlanTask>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) return null;
      final task = PlanTask.tryFromJson(item);
      if (task == null) return null;
      tasks.add(task);
    }
    return tasks;
  } catch (_) {
    return null;
  }
}
