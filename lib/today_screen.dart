import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_screen.dart';
import 'plan_library.dart';
import 'plan_store.dart';
import 'practice_catalog.dart';
import 'profile.dart';
import 'profile_store.dart';
import 'session_engine.dart';
import 'session_screen.dart';
import 'session_store.dart';
import 'today_plan.dart';

const String _lifetimePointsKey = 'cnh.lifetime_points';
const String _doneKeyPrefix = 'cnh.done.';

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _formatDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

String _formatTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// The Today tab: brand header with lifetime points, the pinned
/// impulse card, and the daily plan grouped by section.
///
/// The plan is the user's configured template (Configure Your Day)
/// or the seeded default. Completion is persisted per calendar day
/// keyed by task id; points are lifetime.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool _loading = true;
  bool _editing = false;
  UserProfile _profile = UserProfile.defaults;
  int _lifetimePoints = 0;
  Set<String> _completedIds = <String>{};
  List<PlanTask> _tasks = List<PlanTask>.of(seedTasks);
  late final String _todayDoneKey;

  @override
  void initState() {
    super.initState();
    _todayDoneKey = '$_doneKeyPrefix${_dateKey(DateTime.now())}';
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final tasks = await PlanStore.loadPlan();
    final profile = await ProfileStore.loadProfile();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _profile = profile;
      _lifetimePoints = prefs.getInt(_lifetimePointsKey) ?? 0;
      _completedIds = (prefs.getStringList(_todayDoneKey) ?? []).toSet();
      _loading = false;
    });
  }

  /// Opens the profile in the onboarding flow's edit mode; when
  /// the user saves, the greeting above reflects the new profile.
  Future<void> _openProfile() async {
    final saved = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute<UserProfile>(
        builder: (_) => OnboardingScreen(initial: _profile, editMode: true),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => _profile = saved);
  }

  Future<void> _savePlan() => PlanStore.savePlan(_tasks);

  Future<void> _toggle(PlanTask task, bool complete) async {
    final outcome = toggleTask(
      completedIds: _completedIds,
      lifetimePoints: _lifetimePoints,
      taskId: task.id,
      complete: complete,
    );
    setState(() {
      _completedIds = outcome.completedIds;
      _lifetimePoints = outcome.lifetimePoints;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lifetimePointsKey, _lifetimePoints);
    await prefs.setStringList(_todayDoneKey, _completedIds.toList());
  }

  void _showMilestone3(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // --- Practice launch ----------------------------------------------

  /// The practice a task's play button opens. The 'strength' link
  /// resolves here, at tap time, to today's Upper/Lower routine.
  PracticeDefinition? _practiceFor(PlanTask task) {
    final practiceId = task.practiceId;
    if (task.kind != PlanTaskKind.practice || practiceId == null) {
      return null;
    }
    if (practiceId == strengthPracticeLink) {
      return strengthForDate(DateTime.now());
    }
    return practiceById(practiceId);
  }

  Future<void> _openPractice(PlanTask task) async {
    final practice = _practiceFor(task);
    if (practice == null) return;
    var draft = await SessionStore.loadDraft(cnhDateKey(DateTime.now()));
    if (draft != null && draft.practiceId != practice.id) draft = null;
    if (!mounted) return;
    if (draft != null) {
      // Mirror the tabs' Resume / Start over choice rather than
      // silently dropping an unfinished session.
      final resume = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Unfinished session'),
          content: Text(
            'You have an unfinished ${practice.title} session from today.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Start over'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (resume == null || !mounted) return;
      if (!resume) {
        await SessionStore.clearDraft();
        draft = null;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(practice: practice, draft: draft),
      ),
    );
    // A finished session awards points into the shared lifetime
    // total — reload so the chip and checks reflect it.
    await _load();
  }

  // --- Configure Your Day -------------------------------------------

  void _deleteTask(PlanTask task) {
    setState(() => _tasks = removeTask(_tasks, task.id));
    unawaited(_savePlan());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${task.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _reschedule(PlanTask task) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: task.hour, minute: task.minute),
    );
    if (picked == null || !mounted) return;
    final formatted = _formatTime(picked.hour, picked.minute);
    if (formatted == task.time) return;
    setState(() => _tasks = rescheduleTask(_tasks, task.id, formatted));
    unawaited(_savePlan());
  }

  void _onReorder(int oldIndex, int newIndex) {
    // ReorderableListView indexes the displayed (time-sorted) list;
    // the result becomes the stored manual order.
    final display = sortedPlan(_tasks);
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final next = List<PlanTask>.of(display);
    final moved = next.removeAt(oldIndex);
    next.insert(target, moved);
    setState(() => _tasks = next);
    unawaited(_savePlan());
  }

  void _addFromLibrary(PlanLibraryEntry entry) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(); // Close the library sheet.
    final added = tryAddTask(_tasks, entry.toTask());
    if (added == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${entry.name} is already in your day.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _tasks = added);
    unawaited(_savePlan());
    messenger.showSnackBar(
      SnackBar(
        content: Text('${entry.name} added to your day.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showLibrary() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Add from library',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final category in PlanCategory.values) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            category.label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        for (final entry in libraryEntriesFor(category))
                          ListTile(
                            title: Text(entry.name),
                            subtitle: Text(
                              entry.kind == PlanTaskKind.practice
                                  ? 'Practice · ${entry.defaultTime}'
                                  : 'Daily habit · ${entry.defaultTime}',
                            ),
                            trailing: Icon(
                              _tasks.any((task) => task.id == entry.id)
                                  ? Icons.check
                                  : Icons.add,
                            ),
                            onTap: () => _addFromLibrary(entry),
                          ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset to defaults?'),
        content: const Text(
          'Your day goes back to the original 13 tasks. '
          'Points and history are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await PlanStore.resetToDefaults();
    if (!mounted) return;
    setState(() => _tasks = List<PlanTask>.of(seedTasks));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Back to the default day.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // --- Build ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    return SafeArea(
      child: _editing ? _buildEditMode(theme) : _buildNormalMode(theme),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final gold = theme.colorScheme.secondary;
    final now = DateTime.now();
    final firstName = _profile.firstName;
    final greeting =
        '${greetingForHour(now.hour)}${firstName.isEmpty ? '' : ', $firstName'}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Calm n Healthy',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                greeting,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(now),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Chip(
          avatar: Icon(Icons.star, size: 18, color: gold),
          label: Text(
            '$_lifetimePoints pts',
            style: TextStyle(color: gold, fontWeight: FontWeight.bold),
          ),
          side: BorderSide(color: gold.withValues(alpha: 0.5)),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.person_outline),
          tooltip: 'Your profile',
          onPressed: _openProfile,
        ),
        IconButton(
          icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
          tooltip: _editing ? 'Done' : 'Configure your day',
          onPressed: () => setState(() => _editing = !_editing),
        ),
      ],
    );
  }

  Widget _buildNormalMode(ThemeData theme) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final sections = groupBySection(sortedPlan(_tasks));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildHeader(theme),
        const SizedBox(height: 16),
        _buildImpulseCard(theme),
        const SizedBox(height: 8),
        if (_tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Your day is empty. Tap the pencil — Configure your '
              'day — to add from the library.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final section in PlanSection.values)
          if (sections[section]!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                section.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final task in sections[section]!)
              _buildTaskRow(theme, task, nowMinutes),
          ],
      ],
    );
  }

  Widget _buildEditMode(ThemeData theme) {
    final display = sortedPlan(_tasks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildHeader(theme),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure your day',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Drag to reorder · tap a time to reschedule.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: display.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) =>
                _buildEditRow(theme, display[index], index),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmReset(),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset to defaults'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showLibrary(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add from library'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditRow(ThemeData theme, PlanTask task, int index) {
    return ListTile(
      key: ValueKey(task.id),
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(task.name),
      subtitle: Text(
        task.kind == PlanTaskKind.practice ? 'Practice' : 'Daily habit',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _reschedule(task),
            child: Text(task.time),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove ${task.name}',
            onPressed: () => _deleteTask(task),
          ),
        ],
      ),
    );
  }

  Widget _buildImpulseCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pause first',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'One minute of breath before the moment decides for you.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _showMilestone3(
                      'Before eating',
                      'The one-minute breathing pause before eating '
                          'arrives in Milestone 3.',
                    ),
                    child: const Text('Before eating'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _showMilestone3(
                      'Before scrolling',
                      'The one-minute breathing pause before scrolling '
                          'arrives in Milestone 3.',
                    ),
                    child: const Text('Before scrolling'),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _showMilestone3(
                  'Help me now',
                  'Support for strong moments arrives in Milestone 3.',
                ),
                child: const Text('Help me now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskRow(ThemeData theme, PlanTask task, int nowMinutes) {
    final completed = _completedIds.contains(task.id);
    final overdue = isOverdue(
      task,
      nowMinutesOfDay: nowMinutes,
      completed: completed,
    );
    final Color? nameColor = completed
        ? Colors.green.shade400
        : overdue
        ? Colors.amber
        : null;
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            task.time,
            style: theme.textTheme.bodyMedium?.copyWith(color: nameColor),
          ),
        ),
        Expanded(
          child: Text(
            task.name,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: nameColor,
              decoration: completed ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (task.kind == PlanTaskKind.practice)
          IconButton(
            icon: Icon(
              Icons.play_circle_outline,
              color: theme.colorScheme.secondary,
            ),
            tooltip: 'Start ${task.name}',
            onPressed: () => _openPractice(task),
          ),
        if (overdue)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Overdue',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Checkbox(
          value: completed,
          activeColor: Colors.green.shade600,
          onChanged: (value) => _toggle(task, value ?? false),
        ),
      ],
    );
  }
}
