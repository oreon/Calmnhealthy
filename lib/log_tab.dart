import 'package:flutter/material.dart';

import 'session_engine.dart';
import 'session_store.dart';

/// The Log tab: today's completed guided sessions, with an honest
/// empty state until the first one is saved.
class LogTab extends StatefulWidget {
  const LogTab({super.key});

  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> {
  List<SessionLogEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    SessionStore.changes.addListener(_load);
  }

  @override
  void dispose() {
    SessionStore.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await SessionStore.logForDate(cnhDateKey(DateTime.now()));
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _timeOf(SessionLogEntry entry) {
    final parsed = DateTime.tryParse(entry.timestamp);
    if (parsed == null) return '';
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

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
          Text(
            'Completed sessions today',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_entries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No completed sessions yet today. When you finish a '
                  'practice from the Exercise or Meditate tab and save '
                  'it, it will appear here.',
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
