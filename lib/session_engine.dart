/// Pure-Dart session engine for guided practices, plus the persisted
/// session-draft model. No Flutter imports — fully unit-testable.
///
/// Time accounting is honest, mirroring the rule the old app settled
/// on: only seconds ticked while running AND in a work phase count as
/// active practice. Paused time, rest phases and the unpracticed
/// remainder of a skipped step never count.
library;

import 'dart:math';

import 'practice_catalog.dart';

/// Points for a guided session: two points per completed active
/// minute, capped at 120 points (one hour) per session.
int sessionPoints(int activeSeconds) {
  if (activeSeconds <= 0) return 0;
  return min(120, 2 * (activeSeconds ~/ 60));
}

/// The phase a session is in.
enum SessionPhase { work, rest, done }

/// Formats a date as the 'yyyy-MM-dd' key used across the app's
/// per-day SharedPreferences records.
String cnhDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Drives one run of a [PracticeDefinition]: counts down each step,
/// inserts rests between steps, tracks sets, and accumulates only
/// active (worked, unpaused) seconds.
class SessionEngine {
  final PracticeDefinition practice;

  /// 0-based index of the current step.
  int exerciseIndex;

  /// 1-based current set.
  int set;

  /// Actively practiced seconds so far (pauses/rests/skips excluded).
  int activeSeconds;

  SessionPhase phase = SessionPhase.work;

  /// Seconds left in the current phase.
  int secondsRemaining;

  /// Whether the clock is running (false when paused or done).
  bool running = true;

  final List<String> _skippedKeys;

  SessionEngine(
    this.practice, {
    this.exerciseIndex = 0,
    this.set = 1,
    this.activeSeconds = 0,
    List<String> skippedKeys = const [],
  }) : secondsRemaining = practice.steps[exerciseIndex].seconds,
       _skippedKeys = List<String>.of(skippedKeys);

  bool get isDone => phase == SessionPhase.done;
  bool get isResting => phase == SessionPhase.rest;

  /// 1-based counter of the current step, for 'Exercise X of Y'.
  int get exerciseNumber => exerciseIndex + 1;
  int get exerciseTotal => practice.steps.length;
  int get setNumber => set;
  int get setTotal => practice.sets;

  PracticeStep get currentStep => practice.steps[exerciseIndex];

  /// 'work' while practising, 'rest' while resting.
  String get phaseLabel => switch (phase) {
    SessionPhase.work => currentStep.name,
    SessionPhase.rest => 'Rest',
    SessionPhase.done => 'Done',
  };

  bool get hasSkips => _skippedKeys.isNotEmpty;
  List<String> get skippedKeys => List.unmodifiable(_skippedKeys);

  /// Points this session has earned so far.
  int get pointsEarned => sessionPoints(activeSeconds);

  void pause() => running = false;

  void resume() {
    if (!isDone) running = true;
  }

  /// Advances the session by one second. Only a running work phase
  /// adds to [activeSeconds].
  void tick() {
    if (!running || isDone) return;
    if (phase == SessionPhase.work) {
      activeSeconds++;
    }
    secondsRemaining--;
    if (secondsRemaining <= 0) {
      _finishPhase();
    }
  }

  /// Ends the current step's remaining work immediately. The skipped
  /// remainder is never counted. During a rest, skips the rest.
  void skip() {
    if (isDone) return;
    if (phase == SessionPhase.work) {
      _skippedKeys.add('$exerciseIndex:$set');
      _finishPhase();
    } else if (phase == SessionPhase.rest) {
      _startNextStep();
    }
  }

  void _finishPhase() {
    if (phase == SessionPhase.rest) {
      _startNextStep();
      return;
    }
    // A work phase just ended.
    final isLastStep = exerciseIndex >= practice.steps.length - 1;
    final isLastSet = set >= practice.sets;
    if (isLastStep && isLastSet) {
      phase = SessionPhase.done;
      running = false;
      secondsRemaining = 0;
      return;
    }
    if (practice.restSeconds > 0) {
      phase = SessionPhase.rest;
      secondsRemaining = practice.restSeconds;
    } else {
      _startNextStep();
    }
  }

  void _startNextStep() {
    if (exerciseIndex < practice.steps.length - 1) {
      exerciseIndex++;
    } else {
      exerciseIndex = 0;
      set++;
    }
    phase = SessionPhase.work;
    secondsRemaining = practice.steps[exerciseIndex].seconds;
  }
}

/// A persisted checkpoint of an in-progress session.
///
/// A draft is only resumable on the calendar day it was saved (see
/// [SessionDraft.isForDate]); a resumed session reuses the original
/// [sessionKey] so its points can only ever be awarded once.
class SessionDraft {
  final String practiceId;

  /// Points-engine session key minted when the session first started.
  final String sessionKey;

  /// 0-based step index to resume at.
  final int exerciseIndex;

  /// 1-based set to resume at.
  final int set;

  /// Actively practiced seconds so far.
  final int activeSeconds;

  /// Skipped steps so far, as 'exerciseIndex:set' keys.
  final List<String> skippedKeys;

  /// Local date (yyyy-MM-dd) the draft was saved.
  final String date;

  const SessionDraft({
    required this.practiceId,
    required this.sessionKey,
    this.exerciseIndex = 0,
    this.set = 1,
    this.activeSeconds = 0,
    this.skippedKeys = const [],
    required this.date,
  });

  /// Snapshots an engine's resumable state.
  factory SessionDraft.fromEngine(
    SessionEngine engine, {
    required String sessionKey,
    required String date,
  }) => SessionDraft(
    practiceId: engine.practice.id,
    sessionKey: sessionKey,
    exerciseIndex: engine.exerciseIndex,
    set: engine.set,
    activeSeconds: engine.activeSeconds,
    skippedKeys: engine.skippedKeys,
    date: date,
  );

  /// Rebuilds an engine at the saved place. The current step's
  /// countdown restarts in full; earlier active seconds are intact.
  SessionEngine toEngine(PracticeDefinition practice) => SessionEngine(
    practice,
    exerciseIndex: exerciseIndex.clamp(0, practice.steps.length - 1),
    set: set.clamp(1, practice.sets),
    activeSeconds: activeSeconds,
    skippedKeys: skippedKeys,
  );

  /// Whether this draft belongs to the given 'yyyy-MM-dd' day.
  bool isForDate(String dateKey) => date == dateKey;

  Map<String, dynamic> toJson() => {
    'practice_id': practiceId,
    'session_key': sessionKey,
    'exercise_index': exerciseIndex,
    'set': set,
    'active_seconds': activeSeconds,
    'skipped': skippedKeys,
    'date': date,
  };

  /// Decodes a draft; returns null when the payload is unusable.
  static SessionDraft? tryFromJson(Map<String, dynamic> json) {
    final practiceId = json['practice_id'] as String?;
    final sessionKey = json['session_key'] as String?;
    final date = json['date'] as String?;
    if (practiceId == null || sessionKey == null || date == null) {
      return null;
    }
    return SessionDraft(
      practiceId: practiceId,
      sessionKey: sessionKey,
      exerciseIndex: (json['exercise_index'] as num?)?.toInt() ?? 0,
      set: (json['set'] as num?)?.toInt() ?? 1,
      activeSeconds: (json['active_seconds'] as num?)?.toInt() ?? 0,
      skippedKeys:
          (json['skipped'] as List?)
              ?.map((value) => value.toString())
              .toList() ??
          const [],
      date: date,
    );
  }
}
