import 'dart:async';

import 'package:flutter/material.dart';

import 'completion_screen.dart';
import 'practice_catalog.dart';
import 'session_engine.dart';
import 'session_store.dart';

String formatClock(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Runs one practice: big countdown, current step/phase, counters,
/// pause/resume, skip and end. Saves a same-day draft as it goes so
/// an interrupted session can be resumed from its tab.
class SessionScreen extends StatefulWidget {
  final PracticeDefinition practice;

  /// A same-day draft to resume, or null for a fresh start.
  final SessionDraft? draft;

  const SessionScreen({super.key, required this.practice, this.draft});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final SessionEngine _engine;
  late final String _sessionKey;
  Timer? _timer;
  bool _movedToCompletion = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null && draft.practiceId == widget.practice.id) {
      _engine = draft.toEngine(widget.practice);
      _sessionKey = draft.sessionKey;
    } else {
      _engine = SessionEngine(widget.practice);
      _sessionKey =
          '${widget.practice.id}:${cnhDateKey(DateTime.now())}:'
          '${DateTime.now().millisecondsSinceEpoch}';
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _engine.tick());
      _saveDraft();
      if (_engine.isDone) _goToCompletion(endedEarly: false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_movedToCompletion) _saveDraft();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    if (_engine.isDone) return;
    await SessionStore.saveDraft(
      SessionDraft.fromEngine(
        _engine,
        sessionKey: _sessionKey,
        date: cnhDateKey(DateTime.now()),
      ),
    );
  }

  void _goToCompletion({required bool endedEarly}) {
    if (_movedToCompletion) return;
    _movedToCompletion = true;
    _timer?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CompletionScreen(
          practice: widget.practice,
          sessionKey: _sessionKey,
          activeSeconds: _engine.activeSeconds,
          points: _engine.pointsEarned,
          endedEarly: endedEarly,
          hasSkips: _engine.hasSkips,
        ),
      ),
    );
  }

  void _endEarly() {
    if (_engine.activeSeconds <= 0) {
      // Nothing practiced yet: abandon without a log entry, and drop
      // any draft so the tabs offer a clean start.
      SessionStore.clearDraft();
      Navigator.of(context).pop();
      return;
    }
    _goToCompletion(endedEarly: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final practice = widget.practice;
    final resting = _engine.isResting;
    return Scaffold(
      appBar: AppBar(title: Text(practice.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                resting ? 'Rest' : _engine.currentStep.name,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                resting ? 'Next: ${_nextStepName()}' : practice.description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                formatClock(_engine.secondsRemaining),
                textAlign: TextAlign.center,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: resting ? Colors.amber : null,
                ),
              ),
              const SizedBox(height: 8),
              if (practice.isInterval) ...[
                Text(
                  '${practice.unitLabel} ${_engine.exerciseNumber} of '
                  '${_engine.exerciseTotal}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                if (practice.sets > 1)
                  Text(
                    'Set ${_engine.setNumber} of ${_engine.setTotal}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                'Practiced ${formatClock(_engine.activeSeconds)} · '
                '${_engine.pointsEarned} pts so far',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton.icon(
                    onPressed: _endEarly,
                    icon: const Icon(Icons.stop),
                    label: const Text('End'),
                  ),
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      if (_engine.running) {
                        _engine.pause();
                        _saveDraft();
                      } else {
                        _engine.resume();
                      }
                    }),
                    icon: Icon(
                      _engine.running ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(_engine.running ? 'Pause' : 'Resume'),
                  ),
                  if (practice.isInterval)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _engine.skip()),
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nextStepName() {
    final practice = widget.practice;
    if (_engine.exerciseIndex < practice.steps.length - 1) {
      return practice.steps[_engine.exerciseIndex + 1].name;
    }
    return practice.steps.first.name;
  }
}
