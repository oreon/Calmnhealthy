import 'package:calm_n_healthy/main.dart';
import 'package:calm_n_healthy/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SessionStore.debugResetCache();
  });

  testWidgets('Today points chip updates when a session is saved elsewhere', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'cnh.onboarded': true});

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();
    expect(find.text('0 pts'), findsOneWidget);

    await SessionStore.completeSession(
      sessionKey: 'box:widget',
      entry: SessionLogEntry(
        timestamp: DateTime.now().toIso8601String(),
        kind: 'Box breathing',
        practiceId: 'box-breathing',
        activeSeconds: 60,
        points: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 pts'), findsOneWidget);

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(find.text('Box breathing'), findsOneWidget);
    expect(find.text('+2 pts'), findsOneWidget);
  });
}
