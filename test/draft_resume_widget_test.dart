import 'dart:convert';

import 'package:calm_n_healthy/main.dart';
import 'package:calm_n_healthy/session_engine.dart';
import 'package:calm_n_healthy/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SessionStore.debugResetCache();
  });

  testWidgets('Meditate offers Resume for a non-default length and track', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final today = cnhDateKey(DateTime.now());
    SharedPreferences.setMockInitialValues({
      'cnh.onboarded': true,
      SessionStore.draftKey: jsonEncode({
        'practice_id': 'meditation-20',
        'session_key': 'meditation-20:$today:1',
        'active_seconds': 120,
        'audio_track': 'sounds/relax.mp3',
        'date': today,
      }),
    });

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meditate'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '20 min'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Relax'))
          .selected,
      isTrue,
    );
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('Diet offers Resume for an unfinished 15-minute meal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final today = cnhDateKey(DateTime.now());
    SharedPreferences.setMockInitialValues({
      'cnh.onboarded': true,
      SessionStore.draftKey: jsonEncode({
        'practice_id': 'mindful-eating-15',
        'session_key': 'mindful-eating-15:$today:1',
        'active_seconds': 90,
        'audio_track': 'sounds/pre-meals.mp3',
        'date': today,
      }),
    });

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diet'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '15 min'))
          .selected,
      isTrue,
    );
    expect(find.text('Resume'), findsOneWidget);
  });
}
