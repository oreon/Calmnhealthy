import 'dart:async';

import 'package:flutter/material.dart';

import 'audio_service.dart';
import 'breathing.dart';
import 'completion_screen.dart';
import 'practice_catalog.dart';
import 'session_engine.dart';
import 'session_screen.dart' show formatClock;

/// Entry card for one breathing pattern (Meditate tab): title,
/// rhythm and a Start that opens the breathing screen, where the
/// length is chosen.
class BreathingPatternCard extends StatelessWidget {
  final BreathingPattern pattern;

  const BreathingPatternCard({super.key, required this.pattern});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pattern.subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BreathingScreen(pattern: pattern),
                ),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One guided breathing session: pick a length (1/3/5/10 min), then
/// follow the pacer — a circle that grows through the inhale, holds,
/// and shrinks through the exhale — with the phase label and its
/// countdown. Finishing (or ending early with time breathed) lands
/// on the shared completion moment, which awards the points once
/// and logs the session.
///
/// When [autoStartSeconds] is given, the session starts immediately
/// at that length with no setup step — the Today 'Before scrolling'
/// impulse uses this for its 60-second box breathing.
///
/// Box breathing plays a short chime each time the phase changes
/// (and again on resume). The screen used to draw the pacer only:
/// nothing constructed a player, so the session was silent. Other
/// patterns, including 4-7-8, stay silent. [cueAudio] lets tests
/// inject a fake player; production builds one on first start.
class BreathingScreen extends StatefulWidget {
  final BreathingPattern pattern;
  final int? autoStartSeconds;
  final String? introLine;
  final AudioService? cueAudio;

  const BreathingScreen({
    super.key,
    required this.pattern,
    this.autoStartSeconds,
    this.introLine,
    this.cueAudio,
  });

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen> {
  int _selectedMinutes = 3;
  BreathingEngine? _engine;
  late String _sessionKey;
  Timer? _timer;
  bool _movedToCompletion = false;
  AudioService? _cueAudio;

  /// Phase index we already chimed for. Null after a pause so resume
  /// sounds the phase the user is rejoining.
  int? _announcedPhase;

  bool get _chimesPhases => widget.pattern.id == boxBreathingPattern.id;

  @override
  void initState() {
    super.initState();
    final auto = widget.autoStartSeconds;
    if (auto != null) _start(auto);
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_cueAudio?.stop());
    super.dispose();
  }

  void _attachCueAudio() {
    if (!_chimesPhases) return;
    _cueAudio ??= widget.cueAudio ?? AudioService.phaseCues();
  }

  /// Plays the chime once per phase while the clock is running.
  void _announcePhase() {
    final engine = _engine;
    final audio = _cueAudio;
    if (engine == null || audio == null) return;
    if (!engine.running || engine.isDone) return;
    final phase = engine.phaseIndex;
    if (_announcedPhase == phase) return;
    _announcedPhase = phase;
    unawaited(audio.playPhaseChime());
  }

  void _start(int totalSeconds) {
    _engine = BreathingEngine(widget.pattern, totalSeconds: totalSeconds);
    _announcedPhase = null;
    _sessionKey =
        '${widget.pattern.id}:${cnhDateKey(DateTime.now())}:'
        '${DateTime.now().millisecondsSinceEpoch}';
    _attachCueAudio();
    _announcePhase();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final engine = _engine!;
      setState(() => engine.tick());
      if (engine.isDone) {
        _goToCompletion(endedEarly: false);
      } else {
        _announcePhase();
      }
    });
  }

  void _goToCompletion({required bool endedEarly}) {
    if (_movedToCompletion) return;
    _movedToCompletion = true;
    _timer?.cancel();
    unawaited(_cueAudio?.stop());
    final engine = _engine!;
    // The completion moment logs kind from the practice title and
    // practiceId from its id — both are the pattern's, so a saved
    // breathing session lands in the Log as 'Box breathing' or
    // '4-7-8 breathing' just like any other practice.
    final practice = PracticeDefinition(
      id: widget.pattern.id,
      title: widget.pattern.title,
      kind: PracticeKind.pranayama,
      steps: [PracticeStep(widget.pattern.title, engine.totalSeconds)],
      sets: 1,
      restSeconds: 0,
      unitLabel: 'Breath',
      description: widget.pattern.subtitle,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CompletionScreen(
          practice: practice,
          sessionKey: _sessionKey,
          activeSeconds: engine.activeSeconds,
          points: engine.pointsEarned,
          endedEarly: endedEarly,
          hasSkips: false,
        ),
      ),
    );
  }

  void _endEarly() {
    unawaited(_cueAudio?.stop());
    if (_engine == null || _engine!.activeSeconds <= 0) {
      // Nothing breathed yet: leave without a log entry.
      Navigator.of(context).pop();
      return;
    }
    _goToCompletion(endedEarly: true);
  }

  void _togglePause() {
    final engine = _engine!;
    setState(() {
      if (engine.running) {
        engine.pause();
        // Forget the phase so Resume chimes the side we are on.
        _announcedPhase = null;
        unawaited(_cueAudio?.stop());
      } else {
        engine.resume();
      }
    });
    _announcePhase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final engine = _engine;
    return Scaffold(
      appBar: AppBar(title: Text(widget.pattern.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: engine == null ? _buildSetup(theme) : _buildPacer(theme),
        ),
      ),
    );
  }

  Widget _buildSetup(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.pattern.subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _chimesPhases
              ? 'Follow the circle: breathe in as it grows, breathe out '
                    'as it shrinks, and rest in the holds between. '
                    'A soft chime marks each phase.'
              : 'Follow the circle: breathe in as it grows, breathe out '
                    'as it shrinks, and rest in the holds between.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          'How long?',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (final minutes in breathingDurationMinutes)
              ChoiceChip(
                label: Text('$minutes min'),
                selected: _selectedMinutes == minutes,
                onSelected: (_) => setState(() => _selectedMinutes = minutes),
              ),
          ],
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () => setState(() => _start(_selectedMinutes * 60)),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }

  Widget _buildPacer(ThemeData theme) {
    final engine = _engine!;
    final gold = theme.colorScheme.secondary;
    final diameter = 120.0 + 110.0 * engine.breathFullness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.introLine != null) ...[
          Text(
            widget.introLine!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: gold,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          widget.pattern.subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 900),
            curve: Curves.linear,
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gold.withValues(alpha: 0.18),
              border: Border.all(color: gold, width: 2),
            ),
            child: Center(
              child: Text(
                '${engine.secondsLeftInPhase}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          engine.currentPhase.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Cycle ${engine.completedCycles + 1} · '
          '${formatClock(engine.activeSeconds)} of '
          '${formatClock(engine.totalSeconds)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          '${engine.pointsEarned} pts so far',
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
              onPressed: _togglePause,
              icon: Icon(engine.running ? Icons.pause : Icons.play_arrow),
              label: Text(engine.running ? 'Pause' : 'Resume'),
            ),
          ],
        ),
      ],
    );
  }
}
