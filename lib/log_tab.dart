import 'package:flutter/material.dart';

import 'session_engine.dart';
import 'session_store.dart';

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

/// The Log tab: completed guided sessions for one day, today by
/// default, with previous/next day controls so older saved sessions
/// stay reachable. A damaged stored row is counted here and left in
/// storage; it is never shown as a session and never deleted.
class LogTab extends StatefulWidget {
  const LogTab({super.key});

  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> {
  late DateTime _selected;
  List<SessionLogEntry> _entries = const [];
  int _unreadable = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = DateUtils.dateOnly(DateTime.now());
    _load();
    SessionStore.changes.addListener(_load);
  }

  @override
  void dispose() {
    SessionStore.changes.removeListener(_load);
    super.dispose();
  }

  bool get _isToday => DateUtils.isSameDay(_selected, DateTime.now());

  Future<void> _load() async {
    final dateKey = cnhDateKey(_selected);
    final entries = await SessionStore.logForDate(dateKey);
    final unreadable = await SessionStore.unreadableLogEntries();
    if (!mounted || cnhDateKey(_selected) != dateKey) return;
    setState(() {
      _entries = entries;
      _unreadable = unreadable;
      _loading = false;
    });
  }

  void _shift(int days) {
    final next = DateUtils.addDaysToDate(_selected, days);
    final today = DateUtils.dateOnly(DateTime.now());
    if (next.isAfter(today)) return;
    setState(() {
      _selected = next;
      _loading = true;
    });
    _load();
  }

  void _jumpToToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.isSameDay(_selected, today)) return;
    setState(() {
      _selected = today;
      _loading = true;
    });
    _load();
  }

  String _labelFor(DateTime day) {
    final pretty =
        '${_weekdayNames[day.weekday - 1]}, '
        '${_monthNames[day.month - 1]} ${day.day}, ${day.year}';
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.isSameDay(day, today)) return 'Today · $pretty';
    final yesterday = DateUtils.addDaysToDate(today, -1);
    if (DateUtils.isSameDay(day, yesterday)) return 'Yesterday · $pretty';
    return pretty;
  }

  String _timeOf(SessionLogEntry entry) {
    final parsed = DateTime.tryParse(entry.timestamp);
    if (parsed == null) return '';
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get _unreadableNotice => _unreadable == 1
      ? '1 saved entry could not be read. It was left in storage.'
      : '$_unreadable saved entries could not be read. '
            'They were left in storage.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Log',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _labelFor(_selected),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: _isToday ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (!_isToday)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _jumpToToday,
                child: const Text('Back to today'),
              ),
            ),
          const SizedBox(height: 8),
          if (_unreadable > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _unreadableNotice,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_entries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _isToday
                      ? 'No completed sessions yet today. When you finish a '
                            'practice from the Exercise or Meditate tab and save '
                            'it, it will appear here.'
                      : 'No completed sessions on this day.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          else
            for (final entry in _entries.reversed)
              Card(
                child: ListTile(
                  leading: entry.feeling.isNotEmpty
                      ? Text(
                          entry.feeling,
                          style: const TextStyle(fontSize: 24),
                        )
                      : const Icon(Icons.check_circle_outline),
                  title: Text(entry.kind),
                  subtitle: Text(
                    '${_timeOf(entry)} · '
                    '${entry.activeMinutes} min practised'
                    '${entry.reflection.isNotEmpty ? '\n${entry.reflection}' : ''}',
                  ),
                  trailing: Text(
                    '+${entry.points} pts',
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
