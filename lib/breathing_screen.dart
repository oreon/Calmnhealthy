import 'dart:async';

import 'package:flutter/material.dart';

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
class BreathingScreen extends StatefulWidget {
  final BreathingPattern pattern;
  final int? autoStartSeconds;
  final String? introLine;

  const BreathingScreen({
    super.key,
    required this.pattern,
    this.autoStartSeconds,
    this.introLine,
  });

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen>
    with WidgetsBindingObserver {
  int _selectedMinutes = 3;
  BreathingEngine? _engine;
  late String _sessionKey;
  Timer? _timer;
  bool _movedToCompletion = false;

  /// Wall-clock moment the engine was last advanced to. Android
  /// pauses the periodic timer while the screen is off, so elapsed
  /// time is derived from the clock and applied via
  /// [BreathingEngine.advance] — breathed time is never stalled.
  DateTime _lastAdvance = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auto = widget.autoStartSeconds;
    if (auto != null) _start(auto);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _start(int totalSeconds) {
    _engine = BreathingEngine(widget.pattern, totalSeconds: totalSeconds);
    _sessionKey =
        '${widget.pattern.id}:${cnhDateKey(DateTime.now())}:'
        '${DateTime.now().millisecondsSinceEpoch}';
    _lastAdvance = DateTime.now();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _advanceFromClock(),
    );
  }

  /// Applies the real elapsed time since the last advance. Runs on
  /// every timer tick and on return to the foreground; the baseline
  /// moves even while paused, so paused time never counts later.
  void _advanceFromClock() {
    if (!mounted || _engine == null) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastAdvance).inSeconds;
    if (elapsed <= 0) return;
    _lastAdvance = _lastAdvance.add(Duration(seconds: elapsed));
    setState(() => _engine!.advance(elapsed));
    if (_engine!.isDone) _goToCompletion(endedEarly: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _advanceFromClock();
    }
  }

  void _goToCompletion({required bool endedEarly}) {
    if (_movedToCompletion) return;
    _movedToCompletion = true;
    _timer?.cancel();
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
      } else {
        engine.resume();
      }
    });
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
          'Follow the circle: breathe in as it grows, breathe out '
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
