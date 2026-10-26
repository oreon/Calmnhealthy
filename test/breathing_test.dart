// Box breathing + 4-7-8 breathing: patterns, engine, library
// entries, and the mindful-eating catalog practice (v2.4.0).

import 'package:calm_n_healthy/breathing.dart';
import 'package:calm_n_healthy/plan_library.dart';
import 'package:calm_n_healthy/practice_catalog.dart';
import 'package:calm_n_healthy/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('patterns', () {
    test('box is 4-4-4-4, a 16-second cycle', () {
      expect(boxBreathingPattern.title, 'Box breathing');
      expect(boxBreathingPattern.rhythmLabel, '4 · 4 · 4 · 4');
      expect(
        boxBreathingPattern.phases.map((p) => (p.label, p.seconds)),
        [('Inhale', 4), ('Hold', 4), ('Exhale', 4), ('Hold', 4)],
      );
      expect(boxBreathingPattern.cycleSeconds, 16);
    });

    test('4-7-8 is inhale 4, hold 7, exhale 8 — a 19-second cycle', () {
      expect(fourSevenEightPattern.title, '4-7-8 breathing');
      expect(fourSevenEightPattern.subtitle, '4 · 7 · 8, for sleep and calm');
      expect(
        fourSevenEightPattern.phases.map((p) => (p.label, p.seconds)),
        [('Inhale', 4), ('Hold', 7), ('Exhale', 8)],
      );
      expect(fourSevenEightPattern.cycleSeconds, 19);
    });

    test('patterns resolve by id', () {
      expect(breathingPatternById('box-breathing'), boxBreathingPattern);
      expect(breathingPatternById('breathing-4-7-8'), fourSevenEightPattern);
      expect(breathingPatternById('nope'), isNull);
    });
  });

  group('engine phase boundaries — box', () {
    BreathingEngine engineAt(int seconds) {
      final engine = BreathingEngine(
        boxBreathingPattern,
        totalSeconds: 3600,
      );
      for (var i = 0; i < seconds; i++) {
        engine.tick();
      }
      return engine;
    }

    test('inhale spans 0..3, counting down 4..1', () {
      expect(engineAt(0).currentPhase.label, 'Inhale');
      expect(engineAt(0).secondsLeftInPhase, 4);
      expect(engineAt(3).currentPhase.label, 'Inhale');
      expect(engineAt(3).secondsLeftInPhase, 1);
    });

    test('first hold spans 4..7, exhale 8..11, second hold 12..15', () {
      expect(engineAt(4).currentPhase.label, 'Hold');
      expect(engineAt(7).currentPhase.label, 'Hold');
      expect(engineAt(8).currentPhase.label, 'Exhale');
      expect(engineAt(11).secondsLeftInPhase, 1);
      expect(engineAt(12).currentPhase.label, 'Hold');
      expect(engineAt(15).currentPhase.label, 'Hold');
    });

    test('a completed cycle restarts at Inhale and counts the cycle', () {
      final engine = engineAt(16);
      expect(engine.completedCycles, 1);
      expect(engine.currentPhase.label, 'Inhale');
      expect(engine.secondsLeftInPhase, 4);
      expect(engineAt(35).completedCycles, 2);
    });

    test('fullness rises, holds full, falls, holds empty', () {
      expect(engineAt(0).breathFullness, 0.0);
      expect(engineAt(2).breathFullness, 0.5); // mid-inhale
      expect(engineAt(6).breathFullness, 1.0); // hold after inhale
      expect(engineAt(10).breathFullness, 0.5); // mid-exhale
      expect(engineAt(14).breathFullness, 0.0); // hold after exhale
    });
  });

  group('engine phase boundaries — 4-7-8', () {
    test('inhale 0..3, hold 4..10, exhale 11..18, cycle at 19', () {
      final engine = BreathingEngine(
        fourSevenEightPattern,
        totalSeconds: 3600,
      );
      String labelAt(int seconds) {
        final e = BreathingEngine(fourSevenEightPattern, totalSeconds: 3600);
        for (var i = 0; i < seconds; i++) {
          e.tick();
        }
        return e.currentPhase.label;
      }

      expect(engine.currentPhase.label, 'Inhale');
      expect(labelAt(4), 'Hold');
      expect(labelAt(10), 'Hold');
      expect(labelAt(11), 'Exhale');
      expect(labelAt(18), 'Exhale');
      expect(labelAt(19), 'Inhale');

      final atHold = BreathingEngine(fourSevenEightPattern, totalSeconds: 60);
      for (var i = 0; i < 4; i++) {
        atHold.tick();
      }
      expect(atHold.secondsLeftInPhase, 7);
      // The hold keeps the breath full.
      expect(atHold.breathFullness, 1.0);
    });
  });

  group('engine clock honesty', () {
    test('paused ticks never advance the session', () {
      final engine = BreathingEngine(boxBreathingPattern, totalSeconds: 60);
      engine.tick();
      engine.tick();
      engine.pause();
      for (var i = 0; i < 10; i++) {
        engine.tick();
      }
      expect(engine.activeSeconds, 2);
      expect(engine.currentPhase.label, 'Inhale');
      engine.resume();
      engine.tick();
      expect(engine.activeSeconds, 3);
    });

    test('done at the target length; further ticks do nothing', () {
      final engine = BreathingEngine(boxBreathingPattern, totalSeconds: 5);
      for (var i = 0; i < 12; i++) {
        engine.tick();
      }
      expect(engine.activeSeconds, 5);
      expect(engine.isDone, isTrue);
    });

    test('advance applies screen-off time at once, capped at target', () {
      final engine = BreathingEngine(boxBreathingPattern, totalSeconds: 60);
      engine.advance(30);
      expect(engine.activeSeconds, 30);
      engine.advance(999);
      expect(engine.activeSeconds, 60);
      expect(engine.isDone, isTrue);
    });

    test('advance while paused counts nothing', () {
      final engine = BreathingEngine(boxBreathingPattern, totalSeconds: 60);
      engine.advance(5);
      engine.pause();
      engine.advance(30);
      expect(engine.activeSeconds, 5);
      engine.resume();
      engine.advance(5);
      expect(engine.activeSeconds, 10);
    });

    test('points follow the app rule and cap at 120', () {
      final engine = BreathingEngine(boxBreathingPattern, totalSeconds: 7200);
      expect(engine.pointsEarned, 0);
      engine.activeSeconds = 59;
      expect(engine.pointsEarned, 0);
      engine.activeSeconds = 60;
      expect(engine.pointsEarned, 2);
      engine.activeSeconds = 600;
      expect(engine.pointsEarned, 20);
      engine.activeSeconds = 7200;
      expect(engine.pointsEarned, 120);
    });
  });

  group('library entries', () {
    test('box breathing is a practice entry linking to the pattern', () {
      final entry = planLibraryEntryById('box-breathing');
      expect(entry, isNotNull);
      expect(entry!.category, PlanCategory.breathe);
      expect(entry.kind, PlanTaskKind.practice);
      expect(entry.practiceId, 'box-breathing');
      expect(breathingPatternById(entry.practiceId!), boxBreathingPattern);
    });

    test('4-7-8 breathing is a practice entry linking to the pattern', () {
      final entry = planLibraryEntryById('breathing-4-7-8');
      expect(entry, isNotNull);
      expect(entry!.name, '4-7-8 breathing');
      expect(entry.category, PlanCategory.breathe);
      expect(entry.kind, PlanTaskKind.practice);
      expect(entry.practiceId, 'breathing-4-7-8');
      expect(
        breathingPatternById(entry.practiceId!),
        fourSevenEightPattern,
      );
    });
  });

  group('mindful eating catalog', () {
    test('presets are 5/10/15/20 minutes', () {
      expect(mindfulEatingPresetMinutes, [5, 10, 15, 20]);
    });

    test('a length builds a single-step practice on the pre-meal audio', () {
      final practice = mindfulEatingPractice(15);
      expect(practice.id, 'mindful-eating-15');
      expect(practice.title, 'Mindful eating');
      expect(practice.audioTrack, 'sounds/pre-meals.mp3');
      expect(practice.steps, hasLength(1));
      expect(practice.steps.single.seconds, 15 * 60);
      expect(practice.isInterval, isFalse);
    });

    test('practiceById resolves preset lengths only', () {
      expect(practiceById('mindful-eating-5')?.title, 'Mindful eating');
      expect(practiceById('mindful-eating-20')?.audioTrack,
          'sounds/pre-meals.mp3');
      expect(practiceById('mindful-eating-7'), isNull);
      expect(practiceById('mindful-eating'), isNull);
    });
  });
}
