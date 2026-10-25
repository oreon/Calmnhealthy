import 'package:flutter/material.dart';

import 'practice_catalog.dart';
import 'practice_start.dart';
import 'session_engine.dart';
import 'session_store.dart';

/// The Meditate tab: pick a meditation length and start.
class MeditateTab extends StatefulWidget {
  const MeditateTab({super.key});

  @override
  State<MeditateTab> createState() => _MeditateTabState();
}

class _MeditateTabState extends State<MeditateTab> {
  int _selectedMinutes = 10;
  SessionDraft? _draft;

  @override
  void initState() {
    super.initState();
    _loadDraft();
    SessionStore.changes.addListener(_loadDraft);
  }

  @override
  void dispose() {
    SessionStore.changes.removeListener(_loadDraft);
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final draft = await SessionStore.loadDraft(cnhDateKey(DateTime.now()));
    if (!mounted) return;
    setState(() => _draft = draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final practice = meditationPractice(_selectedMinutes);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Meditate',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a length and sit. The timer counts your sitting '
            'time; pauses never count.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meditation',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final minutes in meditationPresetMinutes)
                        ChoiceChip(
                          label: Text('$minutes min'),
                          selected: _selectedMinutes == minutes,
                          onSelected: (_) =>
                              setState(() => _selectedMinutes = minutes),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PracticeStartActions(
                    practice: practice,
                    draft: _draft,
                    onChanged: _loadDraft,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Buteyko breathing and strong-emotion support arrive in '
            'Milestone 3.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
