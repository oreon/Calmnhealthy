import 'package:calm_n_healthy/audio_service.dart';
import 'package:calm_n_healthy/breathing.dart';
import 'package:calm_n_healthy/breathing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingBackend implements AudioBackend {
  final List<String> plays = [];
  int stops = 0;

  @override
  Future<void> play(String track) async {
    plays.add(track);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    stops++;
  }
}

Future<void> _disposeSession(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
}

void main() {
  testWidgets('box breathing chimes at the start and on each phase change', (
    tester,
  ) async {
    final backend = _RecordingBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: BreathingScreen(
          pattern: boxBreathingPattern,
          autoStartSeconds: 60,
          cueAudio: AudioService(backend: backend),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Inhale'), findsOneWidget);
    expect(backend.plays, [AudioService.phaseChimeTrack]);

    // Four one-second ticks leave the first hold. The chime restarts
    // for that phase and not on the ticks that stay inside it.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.text('Hold'), findsOneWidget);
    expect(backend.plays, [
      AudioService.phaseChimeTrack,
      AudioService.phaseChimeTrack,
    ]);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    final playsWhilePaused = backend.plays.length;

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(backend.plays, hasLength(playsWhilePaused));

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(backend.plays, hasLength(playsWhilePaused + 1));
    expect(backend.stops, greaterThan(0));

    await _disposeSession(tester);
  });

  testWidgets('4-7-8 breathing stays silent', (tester) async {
    final backend = _RecordingBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: BreathingScreen(
          pattern: fourSevenEightPattern,
          autoStartSeconds: 60,
          cueAudio: AudioService(backend: backend),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.text('Hold'), findsOneWidget);
    expect(backend.plays, isEmpty);
    expect(backend.stops, 0);

    await _disposeSession(tester);
  });
}
