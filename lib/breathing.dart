/// Pure-Dart breathing patterns and engine: box breathing and
/// 4-7-8 breathing. No Flutter imports — fully unit-testable.
///
/// Time accounting follows the session engine's honesty rule: only
/// seconds ticked while running count as active practice, and
/// points reuse the app-wide session rule (2 points per active
/// minute, capped at 120).
library;

import 'session_engine.dart' show sessionPoints;

/// One phase of a breathing cycle, e.g. Inhale for 4 seconds.
class BreathingPhase {
  final String label;
  final int seconds;

  const BreathingPhase(this.label, this.seconds);
}

/// A named breathing rhythm: an ordered list of phases that repeat
/// until the chosen session length is reached.
class BreathingPattern {
  /// Stable id — also the plan-task practice link and the id the
  /// completion is logged under.
  final String id;

  /// Display title, e.g. 'Box breathing'. The completion log uses
  /// this as the session kind.
  final String title;

  /// One-line guidance shown on the entry card and session screen.
  final String subtitle;

  final List<BreathingPhase> phases;

  const BreathingPattern({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.phases,
  });

  /// Seconds in one full cycle.
  int get cycleSeconds =>
      phases.fold<int>(0, (sum, phase) => sum + phase.seconds);

  /// The rhythm as counts: '4 · 4 · 4 · 4'.
  String get rhythmLabel => phases.map((phase) => phase.seconds).join(' · ');
}

/// Box breathing: equal sides — inhale, hold, exhale, hold.
const BreathingPattern boxBreathingPattern = BreathingPattern(
  id: 'box-breathing',
  title: 'Box breathing',
  subtitle: '4 · 4 · 4 · 4',
  phases: [
    BreathingPhase('Inhale', 4),
    BreathingPhase('Hold', 4),
    BreathingPhase('Exhale', 4),
    BreathingPhase('Hold', 4),
  ],
);

/// 4-7-8 breathing: a long hold and a slow exhale — for sleep
/// and calm.
const BreathingPattern fourSevenEightPattern = BreathingPattern(
  id: 'breathing-4-7-8',
  title: '4-7-8 breathing',
  subtitle: '4 · 7 · 8, for sleep and calm',
  phases: [
    BreathingPhase('Inhale', 4),
    BreathingPhase('Hold', 7),
    BreathingPhase('Exhale', 8),
  ],
);

/// Every breathing pattern, in display order.
const List<BreathingPattern> breathingPatterns = [
  boxBreathingPattern,
  fourSevenEightPattern,
];

/// The pattern with [id], or null when there is none.
BreathingPattern? breathingPatternById(String id) {
  for (final pattern in breathingPatterns) {
    if (pattern.id == id) return pattern;
  }
  return null;
}

/// Session lengths offered before a breathing session, in minutes.
const List<int> breathingDurationMinutes = [1, 3, 5, 10];

/// Drives one breathing session of a fixed target length.
///
/// The engine's whole state derives from [activeSeconds]: the
/// current phase, the time left in it, the pacer fullness and the
/// completed-cycle count are pure functions of the pattern and the
/// elapsed active seconds, so pausing simply stops the clock.
class BreathingEngine {
  final BreathingPattern pattern;

  /// Target length of the session in seconds.
  final int totalSeconds;

  /// Actively breathed seconds so far (pauses excluded).
  int activeSeconds = 0;

  /// Whether the clock is running (false when paused or done).
  bool running = true;

  BreathingEngine(this.pattern, {required this.totalSeconds});

  bool get isDone => activeSeconds >= totalSeconds;

  /// Points this session has earned so far (the app rule).
  int get pointsEarned => sessionPoints(activeSeconds);

  void pause() => running = false;

  void resume() {
    if (!isDone) running = true;
  }

  /// Advances the session by one second — only while running.
  void tick() => advance(1);

  /// Advances the session by [seconds] at once — wall-clock
  /// catch-up after the OS paused the app (e.g. screen off), so
  /// breathed time is neither lost nor double-counted. Never runs
  /// past the session's target length.
  void advance(int seconds) {
    if (!running || isDone || seconds <= 0) return;
    activeSeconds += seconds;
    if (activeSeconds > totalSeconds) {
      activeSeconds = totalSeconds;
    }
  }

  /// Position within the current cycle, in seconds.
  int get elapsedInCycle => activeSeconds % pattern.cycleSeconds;

  /// Whole cycles fully completed.
  int get completedCycles => activeSeconds ~/ pattern.cycleSeconds;

  /// 0-based index of the phase the current position falls in.
  int get phaseIndex {
    var rest = elapsedInCycle;
    for (var i = 0; i < pattern.phases.length; i++) {
      if (rest < pattern.phases[i].seconds) return i;
      rest -= pattern.phases[i].seconds;
    }
    return pattern.phases.length - 1;
  }

  /// The phase the current position falls in.
  BreathingPhase get currentPhase => pattern.phases[phaseIndex];

  /// Seconds already spent in the current phase.
  int get phaseElapsedSeconds {
    var rest = elapsedInCycle;
    for (var i = 0; i < phaseIndex; i++) {
      rest -= pattern.phases[i].seconds;
    }
    return rest;
  }

  /// Seconds left before the next phase begins (counts 4..1 within
  /// a 4-second phase).
  int get secondsLeftInPhase => currentPhase.seconds - phaseElapsedSeconds;

  /// Progress through the current phase, 0..1.
  double get phaseProgress => phaseElapsedSeconds / currentPhase.seconds;

  /// How full the breath is, 0 (empty) to 1 (full) — drives the
  /// pacer circle: rising through an inhale, falling through an
  /// exhale, held at whichever end the last moving phase reached.
  double get breathFullness {
    switch (currentPhase.label) {
      case 'Inhale':
        return phaseProgress;
      case 'Exhale':
        return 1.0 - phaseProgress;
      default:
        // A hold keeps the fullness the previous moving phase left.
        for (var i = phaseIndex - 1; i >= 0; i--) {
          final label = pattern.phases[i].label;
          if (label == 'Inhale') return 1.0;
          if (label == 'Exhale') return 0.0;
        }
        return 0.0;
    }
  }
}
