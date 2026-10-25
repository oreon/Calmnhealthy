import 'package:flutter/material.dart';

import 'practice_catalog.dart';
import 'session_engine.dart';
import 'session_screen.dart';
import 'session_store.dart';

/// The shared mindful-eating start surface (the Diet tab's card
/// is the full version; Today's 'Before eating' opens this sheet):
/// pick a length, then the guided session starts — the pre-meal
/// audio plays, and the completion moment logs 'Mindful eating'.
/// Awaits the whole session, so callers can refresh afterwards.
Future<void> showMindfulEatingStartSheet(BuildContext context) async {
  var selectedMinutes = 10;
  final chosen = await showModalBottomSheet<int>(
    context: context,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mindful eating',
                  style: theme.textTheme.titleLarge?.copyWith(
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
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final minutes in mindfulEatingPresetMinutes)
                      ChoiceChip(
                        label: Text('$minutes min'),
                        selected: selectedMinutes == minutes,
                        onSelected: (_) =>
                            setSheetState(() => selectedMinutes = minutes),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(selectedMinutes),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  if (chosen == null || !context.mounted) return;
  final practice = mindfulEatingPractice(chosen);
  var draft = await SessionStore.loadDraft(cnhDateKey(DateTime.now()));
  if (draft != null && draft.practiceId != practice.id) draft = null;
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SessionScreen(practice: practice, draft: draft),
    ),
  );
}

/// Start controls for one practice card.
///
/// When a same-day draft exists for the practice, this offers Resume
/// (restoring place, active seconds and session key) and Start over
/// (discarding the draft for a fresh run); otherwise a plain Start.
class PracticeStartActions extends StatelessWidget {
  final PracticeDefinition practice;
  final SessionDraft? draft;

  /// Called after a session returns or a draft is discarded, so the
  /// owning tab can reload its draft state.
  final VoidCallback onChanged;

  const PracticeStartActions({
    super.key,
    required this.practice,
    required this.draft,
    required this.onChanged,
  });

  bool get _hasDraft => draft != null && draft!.practiceId == practice.id;

  Future<void> _open(BuildContext context, {required bool resume}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SessionScreen(practice: practice, draft: resume ? draft : null),
      ),
    );
    onChanged();
  }

  Future<void> _startOver(BuildContext context) async {
    await SessionStore.clearDraft();
    if (!context.mounted) return;
    await _open(context, resume: false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasDraft) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: () => _open(context, resume: false),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      );
    }
    final practiced = draft!.activeSeconds ~/ 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          practiced > 0
              ? 'Unfinished session — $practiced min practised today'
              : 'Unfinished session from today',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => _startOver(context),
              child: const Text('Start over'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _open(context, resume: true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume'),
            ),
          ],
        ),
      ],
    );
  }
}
