// Widget tests for v2.4.0: breathing cards on the Meditate tab,
// starting a box-breathing session, and the Diet tab's mindful
// eating start surface.

import 'package:calm_n_healthy/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Meditate tab shows both breathing cards; '
      'starting Box breathing shows the Inhale phase', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'cnh.onboarded': true});

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Meditate'));
    await tester.pumpAndSettle();

    // The Breathing section offers both patterns.
    expect(find.text('Breathing'), findsOneWidget);
    expect(find.text('Box breathing'), findsOneWidget);
    expect(find.text('4-7-8 breathing'), findsOneWidget);
    expect(find.text('4 · 7 · 8, for sleep and calm'), findsOneWidget);

    // Start Box breathing from its card's Start button (tapping
    // the label: FilledButton.icon's runtime type is a subclass,
    // so find the text inside the card instead).
    final boxCard = find.ancestor(
      of: find.text('Box breathing'),
      matching: find.byType(Card),
    );
    await tester.tap(find.descendant(of: boxCard, matching: find.text('Start')));
    await tester.pumpAndSettle();
    expect(find.text('How long?'), findsOneWidget);

    // Pick 1 min and start: the pacer opens on Inhale.
    await tester.tap(find.widgetWithText(ChoiceChip, '1 min'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Inhale'), findsOneWidget);
    expect(find.text('Cycle 1 · 00:00 of 01:00'), findsOneWidget);

    // Tear the tree down so the session timer is disposed.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('Diet tab starts a mindful-eating session '
      'on the pre-meal practice', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'cnh.onboarded': true});

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Diet'));
    await tester.pumpAndSettle();

    // The mindful-eating card with its length choices.
    expect(find.text('Mindful eating'), findsOneWidget);
    expect(
      find.textContaining('pre-meal guided audio plays'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ChoiceChip, '15 min'), findsOneWidget);
    expect(find.textContaining('later update'), findsOneWidget);

    // Choose 15 min and start: the session screen opens with the
    // mindful-eating practice (its soundtrack binding is asserted
    // in breathing_test via the catalog).
    await tester.tap(find.widgetWithText(ChoiceChip, '15 min'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mindful eating'), findsWidgets);
    expect(find.text('15:00'), findsOneWidget);

    // Tear the tree down so the session timer/audio are disposed.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
