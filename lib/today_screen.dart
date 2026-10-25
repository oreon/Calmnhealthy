import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The Today tab: brand header with lifetime points, the pinned
/// impulse card, and the seeded daily plan grouped by section.
/// Completion is persisted per calendar day; points are lifetime.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool _loading = true;
  int _lifetimePoints = 0;
  Set<String> _completedIds = <String>{};
  late final String _todayDoneKey;

  @override
  void initState() {
    super.initState();
    _todayDoneKey = '$_doneKeyPrefix${_dateKey(DateTime.now())}';
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _lifetimePoints = prefs.getInt(_lifetimePointsKey) ?? 0;
      _completedIds = (prefs.getStringList(_todayDoneKey) ?? []).toSet();
      _loading = false;
    });
  }

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final gold = theme.colorScheme.secondary;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final sections = groupBySection(seedTasks);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calm n Healthy',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(now),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Chip(
                avatar: Icon(Icons.star, size: 18, color: gold),
                label: Text(
                  '$_lifetimePoints pts',
                  style: TextStyle(
                    color: gold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                side: BorderSide(color: gold.withValues(alpha: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildImpulseCard(theme),
          const SizedBox(height: 8),
          for (final section in PlanSection.values)
            if (sections[section]!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text(
                  section.label,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              for (final task in sections[section]!)
                _buildTaskRow(theme, task, nowMinutes),
            ],
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
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'One minute of breath before the moment decides for you.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    final overdue =
        isOverdue(task, nowMinutesOfDay: nowMinutes, completed: completed);
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
