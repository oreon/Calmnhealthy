import 'dart:async';

import 'package:flutter/material.dart';

import 'audio_service.dart';
import 'practice_catalog.dart';
import 'session_screen.dart' show formatClock;
import 'session_store.dart';

/// The five feeling faces offered after a session.
const List<String> feelingFaces = ['😖', '🙁', '😐', '🙂', '😄'];

/// The completion moment: 'Well done!', what was actually earned,
/// an optional feeling face and reflection, and a Save that records
/// the session once (points + log) and returns to the shell.
class CompletionScreen extends StatefulWidget {
  final PracticeDefinition practice;
  final String sessionKey;
  final int activeSeconds;
  final int points;
  final bool endedEarly;
  final bool hasSkips;

  const CompletionScreen({
    super.key,
    required this.practice,
    required this.sessionKey,
    required this.activeSeconds,
    required this.points,
    required this.endedEarly,
    required this.hasSkips,
  });

  @override
  State<CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<CompletionScreen> {
  String _feeling = '';
  final TextEditingController _reflection = TextEditingController();
  final AudioService _audioService = AudioService();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // The service is created only now that a completion screen is
    // actually showing; its guarded bell is best-effort.
    unawaited(_audioService.playCompletionBell());
  }

  @override
  void dispose() {
    _reflection.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    await SessionStore.completeSession(
      sessionKey: widget.sessionKey,
      entry: SessionLogEntry(
        timestamp: now.toIso8601String(),
        kind: widget.practice.title,
        practiceId: widget.practice.id,
        activeSeconds: widget.activeSeconds,
        points: widget.points,
        feeling: _feeling,
        reflection: _reflection.text.trim(),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = theme.colorScheme.secondary;
    return Scaffold(
      appBar: AppBar(title: Text(widget.practice.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            Text(
              'Well done!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.endedEarly
                  ? 'Ended early — the time you practised still counts.'
                  : 'You completed ${widget.practice.title}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stat(theme, formatClock(widget.activeSeconds), 'practised'),
                const SizedBox(width: 32),
                _stat(theme, '${widget.points} pts', 'earned', color: gold),
              ],
            ),
            if (widget.hasSkips) ...[
              const SizedBox(height: 8),
              Text(
                'Skipped steps were not counted.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 32),
            Text(
              'How do you feel?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final face in feelingFaces)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _feeling = _feeling == face ? '' : face),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _feeling == face
                            ? gold.withValues(alpha: 0.25)
                            : Colors.transparent,
                        border: Border.all(
                          color: _feeling == face
                              ? gold
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(face, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _reflection,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reflection (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
              child: const Text('Discard'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(ThemeData theme, String value, String label, {Color? color}) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
