import 'package:flutter/material.dart';

import 'practice_catalog.dart';
import 'practice_start.dart';
import 'session_engine.dart';
import 'session_store.dart';

/// The Diet tab: mindful eating with its guided audio, with more
/// food tools (snapshots, the eating window) still to come.
class DietTab extends StatefulWidget {
  const DietTab({super.key});

  @override
  State<DietTab> createState() => _DietTabState();
}

class _DietTabState extends State<DietTab> {
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
    final practice = mindfulEatingPractice(_selectedMinutes);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Diet',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Count colours, not calories.',
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
                    'Mindful eating',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Eat slowly, one bite at a time, while the '
                    'pre-meal guided audio plays.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final minutes in mindfulEatingPresetMinutes)
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
            'More food tools arrive in a later update — food '
            'snapshots and the eating window are on the way.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
