import 'dart:convert';
import 'dart:io';

import 'package:calm_n_healthy/audio_service.dart';
import 'package:calm_n_healthy/practice_catalog.dart';
import 'package:calm_n_healthy/session_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingBackend implements AudioBackend {
  @override
  Future<void> play(String track) async => throw StateError('no player');

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}
}

class _RecordingBackend implements AudioBackend {
  String? playedTrack;
  bool stopped = false;

  @override
  Future<void> play(String track) async => playedTrack = track;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async => stopped = true;
}

void main() {
  group('catalog media', () {
    test('every Lower step has its bundled movement image', () {
      expect(strengthLower.steps.map((step) => step.imageAsset).toList(), [
        'assets/images/lower/squat.gif',
        'assets/images/lower/lunge.gif',
        'assets/images/lower/lunge.gif',
        'assets/images/lower/side_lunge.gif',
        'assets/images/lower/side_lunge.gif',
        'assets/images/lower/glute_bridge.gif',
      ]);
      expect(strengthLower.audioTrack, workoutAudioTrack);
    });

    test('Upper defers its images but uses the workout track', () {
      expect(
        strengthUpper.steps.every((step) => step.imageAsset == null),
        isTrue,
      );
      expect(strengthUpper.audioTrack, workoutAudioTrack);
    });

    test('every Yoga step except Cobra has an image', () {
      for (final step in yogaPractice.steps) {
        if (step.name == 'Cobra') {
          expect(step.imageAsset, isNull);
        } else {
          expect(step.imageAsset, isNotNull, reason: step.name);
        }
      }
      expect(yogaPractice.audioTrack, yogaAudioTrack);
    });

    test('meditation image and guided-track map are complete', () {
      expect(meditationPractice(10).imageAsset, meditationImageAsset);
      expect(meditationPractice(10).audioTrack, 'sounds/breath.mp3');
      expect(guidedTrackOptions.map((option) => option.label).toList(), [
        'Breath',
        'Body scan',
        'Relax',
        'Silent',
      ]);
      expect(guidedTrackOptions.map((option) => option.audioTrack).toList(), [
        'sounds/breath.mp3',
        'sounds/bodyscan.m4a',
        'sounds/relax.mp3',
        null,
      ]);
      expect(
        meditationPractice(20, audioTrack: 'sounds/relax.mp3').audioTrack,
        'sounds/relax.mp3',
      );
      expect(meditationPractice(20, audioTrack: null).audioTrack, isNull);
    });

    test('pranayama remains silent and imageless', () {
      expect(pranayamaPractice.audioTrack, isNull);
      expect(pranayamaPractice.imageAsset, isNull);
      expect(
        pranayamaPractice.steps.every((step) => step.imageAsset == null),
        isTrue,
      );
    });
  });

  group('catalog asset files', () {
    test('every media path referenced by the catalog exists on disk', () {
      final paths = <String>{meditationImageAsset, restPhaseImageAsset};

      for (final practice in [
        strengthUpper,
        strengthLower,
        yogaPractice,
        pranayamaPractice,
        meditationPractice(10),
      ]) {
        if (practice.imageAsset != null) paths.add(practice.imageAsset!);
        if (practice.audioTrack != null) {
          paths.add('assets/${practice.audioTrack}');
        }
        for (final step in practice.steps) {
          if (step.imageAsset != null) paths.add(step.imageAsset!);
        }
      }
      for (final option in guidedTrackOptions) {
        if (option.audioTrack != null) {
          paths.add('assets/${option.audioTrack}');
        }
      }
      paths.add('assets/${AudioService.completionBellTrack}');

      for (final path in paths) {
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(File(path).lengthSync(), greaterThan(0), reason: path);
      }
    });
  });

  group('audio service guard', () {
    test('a throwing backend is swallowed and reports not playing', () async {
      final service = AudioService(backend: _ThrowingBackend());

      await service.play('sounds/breath.mp3');

      expect(service.isPlaying, isFalse);
      expect(service.currentTrack, isNull);
    });

    test('a working backend reports its selected track', () async {
      final backend = _RecordingBackend();
      final service = AudioService(backend: backend);

      await service.play('sounds/relax.mp3');
      expect(backend.playedTrack, 'sounds/relax.mp3');
      expect(service.isPlaying, isTrue);
      expect(service.currentTrack, 'sounds/relax.mp3');

      await service.stop();
      expect(backend.stopped, isTrue);
      expect(service.isPlaying, isFalse);
      expect(service.currentTrack, isNull);
    });
  });

  group('session draft media', () {
    test('the selected audio track survives JSON round-trip', () {
      const draft = SessionDraft(
        practiceId: 'meditation-20',
        sessionKey: 'meditation-20:2026-10-25:1',
        activeSeconds: 120,
        audioTrack: 'sounds/relax.mp3',
        date: '2026-10-25',
      );

      final decoded = SessionDraft.tryFromJson(
        jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, isNotNull);
      expect(decoded!.audioTrack, 'sounds/relax.mp3');
    });
  });
}
