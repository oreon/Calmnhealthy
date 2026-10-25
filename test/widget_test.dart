// Widget tests for the Calm n Healthy M1 shell and Today plan.

import 'package:calm_n_healthy/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Today shows the seeded plan; checking a task awards 10 points',
      (tester) async {
    // Tall viewport so the whole seeded plan is built without scrolling.
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();

    // Brand header and points chip at zero.
    expect(find.text('Calm n Healthy'), findsWidgets);
    expect(find.text('0 pts'), findsOneWidget);

    // Seeded tasks from each section are present in the list.
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Meditation'), findsOneWidget);
    expect(find.text('Turn phone off'), findsOneWidget);

    // Check the first task (Water) and see the points increase by 10.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('10 pts'), findsOneWidget);

    // Unchecking removes the award again.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('0 pts'), findsOneWidget);
  });

  testWidgets('Impulse button opens the Milestone 3 dialog', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Before eating'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Milestone 3'), findsOneWidget);
  });
}
