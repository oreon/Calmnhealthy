import 'dart:convert';

import 'package:calm_n_healthy/practice_catalog.dart';
import 'package:calm_n_healthy/session_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Advances an engine by [seconds] one-second ticks.
void tickSeconds(SessionEngine engine, int seconds) {
  for (var i = 0; i < seconds; i++) {
    engine.tick();
  }
}

void main() {
  group('session points math', () {
    test('zero and sub-minute practice earns nothing', () {
      expect(sessionPoints(0), 0);
      expect(sessionPoints(59), 0);
    });

    test('two points per active minute', () {
      expect(sessionPoints(60), 2);
      expect(sessionPoints(10 * 60), 20);
      expect(sessionPoints(30 * 60), 60);
    });

    test('capped at 120 points', () {
      expect(sessionPoints(60 * 60), 120);
      expect(sessionPoints(90 * 60), 120);
    });
  });

  group('engine time accounting', () {
    test('paused ticks never count', () {
      final engine = SessionEngine(strengthUpper);
      tickSeconds(engine, 10);
      engine.pause();
      tickSeconds(engine, 30);
      expect(engine.activeSeconds, 10);
      engine.resume();
      tickSeconds(engine, 5);
      expect(engine.activeSeconds, 15);
    });

    test('rest ticks never count', () {
      final engine = SessionEngine(strengthUpper);
      tickSeconds(engine, 45); // first exercise finishes -> rest
      expect(engine.phase, SessionPhase.rest);
      expect(engine.activeSeconds, 45);
      tickSeconds(engine, 15); // rest finishes -> next exercise
      expect(engine.phase, SessionPhase.work);
      expect(engine.activeSeconds, 45);
      expect(engine.exerciseIndex, 1);
    });

    test('skipped remainder never counts', () {
      final engine = SessionEngine(strengthUpper);
      tickSeconds(engine, 10);
      engine.skip();
      expect(engine.hasSkips, isTrue);
      expect(engine.activeSeconds, 10);
      expect(engine.phase, SessionPhase.rest);
      tickSeconds(engine, 15);
      expect(engine.exerciseIndex, 1);
      expect(engine.activeSeconds, 10);
    });

    test('runs to done with correct totals and counters', () {
      final engine = SessionEngine(strengthUpper);
      // 5 exercises x 45s x 3 sets = 675 active seconds; rests between.
      var guard = 0;
      while (!engine.isDone && guard++ < 10000) {
        engine.tick();
      }
      expect(engine.isDone, isTrue);
      expect(engine.activeSeconds, 675);
      expect(engine.pointsEarned, 22);
      expect(engine.exerciseNumber, 5);
      expect(engine.setNumber, 3);
    });
  });

  group('wall-clock advance (screen-off catch-up)', () {
    test('advance matches one-second ticks across phases', () {
      final ticked = SessionEngine(strengthUpper);
      final advanced = SessionEngine(strengthUpper);
      tickSeconds(ticked, 200);
      advanced.advance(200);
      expect(advanced.activeSeconds, ticked.activeSeconds);
      expect(advanced.phase, ticked.phase);
      expect(advanced.exerciseIndex, ticked.exerciseIndex);
      expect(advanced.secondsRemaining, ticked.secondsRemaining);
    });

    test('advance while paused counts nothing', () {
      final engine = SessionEngine(strengthUpper);
      engine.advance(10);
      engine.pause();
      engine.advance(600);
      expect(engine.activeSeconds, 10);
      engine.resume();
      engine.advance(5);
      expect(engine.activeSeconds, 15);
    });

    test('advancing past the end finishes with honest totals', () {
      final engine = SessionEngine(strengthUpper);
      engine.advance(100000);
      expect(engine.isDone, isTrue);
      // Only real work counts: 5 exercises x 45s x 3 sets.
      expect(engine.activeSeconds, 675);
    });
  });

  group('strength alternation', () {
    test('odd day-of-year is Upper, even is Lower', () {
      expect(dayOfYear(DateTime(2026, 1, 1)), 1);
      expect(strengthForDate(DateTime(2026, 1, 1)).id, 'strength-upper');
      expect(strengthForDate(DateTime(2026, 1, 2)).id, 'strength-lower');
    });

    test('year boundaries: non-leap Dec 31 odd, leap Dec 31 even', () {
      expect(dayOfYear(DateTime(2026, 12, 31)), 365);
      expect(strengthForDate(DateTime(2026, 12, 31)).id, 'strength-upper');
      expect(dayOfYear(DateTime(2024, 12, 31)), 366);
      expect(strengthForDate(DateTime(2024, 12, 31)).id, 'strength-lower');
    });
  });

  group('catalog sanity', () {
    test('Upper list is exact, at 45/15/3', () {
      expect(strengthUpper.steps.map((s) => s.name).toList(), [
        'Pushups',
        'Plank Ups',
        'Plank to Dolphin',
        'Superman',
        'Plank',
      ]);
      expect(strengthUpper.steps.every((s) => s.seconds == 45), isTrue);
      expect(strengthUpper.restSeconds, 15);
      expect(strengthUpper.sets, 3);
    });

    test('Lower list from the old app content, at 45/15/3', () {
      expect(strengthLower.steps.map((s) => s.name).toList(), [
        'Squats',
        'Right Lunge',
        'Left Lunge',
        'Side Lunges Right',
        'Side Lunges Left',
        'Glute Bridge',
      ]);
      expect(strengthLower.restSeconds, 15);
      expect(strengthLower.sets, 3);
    });

    test('yoga sequence from the old app content', () {
      expect(yogaPractice.steps, hasLength(10));
      expect(yogaPractice.steps.first.name, 'Downward Dog');
      expect(yogaPractice.steps.first.seconds, 40);
      expect(yogaPractice.steps.last.name, 'Shavasana (corpse)');
      expect(yogaPractice.steps.last.seconds, 180);
      expect(yogaPractice.sets, 1);
    });

    test('pranayama sequence from the old app content', () {
      expect(pranayamaPractice.steps.map((s) => s.name).toList(), [
        'Bhastrika',
        'Kapalbhati',
        'Nadi Shodhan',
        'Bhramari',
        'Ujjayi',
      ]);
      expect(pranayamaPractice.sets, 1);
    });

    test('meditation presets resolve by id', () {
      expect(meditationPresetMinutes, [5, 10, 20, 30, 45]);
      final ten = practiceById('meditation-10');
      expect(ten, isNotNull);
      expect(ten!.steps.single.seconds, 600);
      expect(practiceById('meditation-15'), isNull);
      expect(practiceById('yoga')!.title, 'Yoga');
      expect(practiceById('nope'), isNull);
    });
  });

  group('session draft', () {
    test('encode/decode round trip', () {
      const draft = SessionDraft(
        practiceId: 'strength-upper',
        sessionKey: 'strength-upper:2026-10-25:123',
        exerciseIndex: 2,
        set: 2,
        activeSeconds: 300,
        skippedKeys: ['1:1'],
        date: '2026-10-25',
      );
      final decoded = SessionDraft.tryFromJson(
        jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, isNotNull);
      expect(decoded!.practiceId, draft.practiceId);
      expect(decoded.sessionKey, draft.sessionKey);
      expect(decoded.exerciseIndex, 2);
      expect(decoded.set, 2);
      expect(decoded.activeSeconds, 300);
      expect(decoded.skippedKeys, ['1:1']);
      expect(decoded.date, '2026-10-25');
    });

    test('stale-date drafts are rejected', () {
      const draft = SessionDraft(
        practiceId: 'yoga',
        sessionKey: 'yoga:2026-10-24:1',
        date: '2026-10-24',
      );
      expect(draft.isForDate('2026-10-24'), isTrue);
      expect(draft.isForDate('2026-10-25'), isFalse);
    });

    test('unusable payloads decode to null', () {
      expect(SessionDraft.tryFromJson({}), isNull);
      expect(SessionDraft.tryFromJson({'practice_id': 'yoga'}), isNull);
    });

    test('draft restores an engine at the saved place', () {
      const draft = SessionDraft(
        practiceId: 'strength-upper',
        sessionKey: 'k',
        exerciseIndex: 3,
        set: 2,
        activeSeconds: 400,
        skippedKeys: ['0:1'],
        date: '2026-10-25',
      );
      final engine = draft.toEngine(strengthUpper);
      expect(engine.exerciseIndex, 3);
      expect(engine.set, 2);
      expect(engine.activeSeconds, 400);
      expect(engine.hasSkips, isTrue);
      expect(engine.secondsRemaining, 45);
    });
  });
}
