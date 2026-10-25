import 'package:flutter/material.dart';

import 'practice_catalog.dart';
import 'session_engine.dart';
import 'session_screen.dart';
import 'session_store.dart';

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
