/// The Configure Your Day library: every item a user can add to
/// their day, grouped by category. Pure Dart (no Flutter imports).
///
/// Item ids deliberately match the seeded plan's task ids for the
/// items both share, so adding e.g. Strength when it is already in
/// the day is recognized as a duplicate and rejected.
library;

import 'today_plan.dart';

/// Library groupings, in display order.
enum PlanCategory { meditate, move, breathe, habits }

extension PlanCategoryLabel on PlanCategory {
  String get label => switch (this) {
    PlanCategory.meditate => 'Meditate',
    PlanCategory.move => 'Move',
    PlanCategory.breathe => 'Breathe',
    PlanCategory.habits => 'Daily habits',
  };
}

/// One addable item in the library.
class PlanLibraryEntry {
  final String id;
  final String name;
  final PlanCategory category;

  /// Time the task lands at when added; reschedulable afterwards
  /// in Configure Your Day edit mode.
  final String defaultTime;

  final PlanTaskKind kind;

  /// For practice items: the practice to open from the Today row —
  /// a catalog practice id, or [strengthPracticeLink].
  final String? practiceId;

  const PlanLibraryEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.defaultTime,
    this.kind = PlanTaskKind.simple,
    this.practiceId,
  });

  /// The plan task this entry adds.
  PlanTask toTask() => PlanTask(
    id: id,
    name: name,
    time: defaultTime,
    kind: kind,
    practiceId: practiceId,
  );
}

/// Every addable item, grouped by category in display order.
const List<PlanLibraryEntry> planLibrary = [
  // Meditate — one entry per guided-meditation preset length.
  PlanLibraryEntry(
    id: 'meditation-5',
    name: 'Meditation 5 min',
    category: PlanCategory.meditate,
    defaultTime: '06:20',
    kind: PlanTaskKind.practice,
    practiceId: 'meditation-5',
  ),
  PlanLibraryEntry(
    id: 'meditation-10',
    name: 'Meditation 10 min',
    category: PlanCategory.meditate,
    defaultTime: '06:20',
    kind: PlanTaskKind.practice,
    practiceId: 'meditation-10',
  ),
  PlanLibraryEntry(
    id: 'meditation-20',
    name: 'Meditation 20 min',
    category: PlanCategory.meditate,
    defaultTime: '06:20',
    kind: PlanTaskKind.practice,
    practiceId: 'meditation-20',
  ),
  PlanLibraryEntry(
    id: 'meditation-30',
    name: 'Meditation 30 min',
    category: PlanCategory.meditate,
    defaultTime: '06:20',
    kind: PlanTaskKind.practice,
    practiceId: 'meditation-30',
  ),
  PlanLibraryEntry(
    id: 'meditation-45',
    name: 'Meditation 45 min',
    category: PlanCategory.meditate,
    defaultTime: '06:20',
    kind: PlanTaskKind.practice,
    practiceId: 'meditation-45',
  ),
  // Move.
  PlanLibraryEntry(
    id: 'strength',
    name: 'Strength',
    category: PlanCategory.move,
    defaultTime: '07:00',
    kind: PlanTaskKind.practice,
    practiceId: strengthPracticeLink,
  ),
  PlanLibraryEntry(
    id: 'yoga',
    name: 'Yoga',
    category: PlanCategory.move,
    defaultTime: '07:30',
    kind: PlanTaskKind.practice,
    practiceId: 'yoga',
  ),
  // Breathe.
  PlanLibraryEntry(
    id: 'pranayama',
    name: 'Pranayama',
    category: PlanCategory.breathe,
    defaultTime: '06:45',
    kind: PlanTaskKind.practice,
    practiceId: 'pranayama',
  ),
  PlanLibraryEntry(
    id: 'box-breathing',
    name: 'Box breathing',
    category: PlanCategory.breathe,
    defaultTime: '14:00',
    kind: PlanTaskKind.practice,
    practiceId: 'box-breathing',
  ),
  PlanLibraryEntry(
    id: 'breathing-4-7-8',
    name: '4-7-8 breathing',
    category: PlanCategory.breathe,
    defaultTime: '20:10',
    kind: PlanTaskKind.practice,
    practiceId: 'breathing-4-7-8',
  ),
  // Daily habits.
  PlanLibraryEntry(
    id: 'water',
    name: 'Water',
    category: PlanCategory.habits,
    defaultTime: '06:00',
  ),
  PlanLibraryEntry(
    id: 'mindful-breakfast',
    name: 'Mindful breakfast',
    category: PlanCategory.habits,
    defaultTime: '08:00',
  ),
  PlanLibraryEntry(
    id: 'mindful-lunch',
    name: 'Mindful lunch',
    category: PlanCategory.habits,
    defaultTime: '13:30',
  ),
  PlanLibraryEntry(
    id: 'fluid-reminder',
    name: 'Fluid reminder',
    category: PlanCategory.habits,
    defaultTime: '15:00',
  ),
  PlanLibraryEntry(
    id: 'wind-down',
    name: 'Wind down',
    category: PlanCategory.habits,
    defaultTime: '19:30',
  ),
  PlanLibraryEntry(
    id: 'journal',
    name: 'Journal',
    category: PlanCategory.habits,
    defaultTime: '19:45',
  ),
  PlanLibraryEntry(
    id: 'phone-off',
    name: 'Turn phone off',
    category: PlanCategory.habits,
    defaultTime: '20:00',
  ),
];

/// The library entries in one category, in display order.
List<PlanLibraryEntry> libraryEntriesFor(PlanCategory category) => [
  for (final entry in planLibrary)
    if (entry.category == category) entry,
];

/// The library entry with [id], or null when there is none.
PlanLibraryEntry? planLibraryEntryById(String id) {
  for (final entry in planLibrary) {
    if (entry.id == id) return entry;
  }
  return null;
}
