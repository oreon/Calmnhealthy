// Widget test for Configure Your Day: open edit mode, add a
// practice from the library, and see it in the day; adding it a
// second time is rejected with the friendly message.

import 'package:calm_n_healthy/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Configure your day adds Pranayama from the library', (
    tester,
  ) async {
    // Tall viewport so the whole plan is built without scrolling.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CalmNHealthyApp());
    await tester.pumpAndSettle();

    // Enter edit mode.
    await tester.tap(find.byTooltip('Configure your day'));
    await tester.pumpAndSettle();
    expect(find.text('Configure your day'), findsWidgets);
    expect(find.text('Add from library'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsOneWidget);

    // The sheet entry for a library item (scoped to the sheet,
    // since an added item's name also appears in the list behind).
    Finder sheetEntry(String name) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(name),
    );

    // Open the library and add Pranayama (not in the seeded day).
    await tester.tap(find.text('Add from library'));
    await tester.pumpAndSettle();
    expect(sheetEntry('Pranayama'), findsOneWidget);
    await tester.tap(sheetEntry('Pranayama'));
    await tester.pumpAndSettle();
    expect(find.text('Pranayama added to your day.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // SnackBar expires.
    await tester.pumpAndSettle();

    // Back in edit mode the new task is listed; leaving edit mode
    // shows it as a normal Morning row (default time 06:45).
    expect(find.text('Pranayama'), findsWidgets);
    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Pranayama'), findsOneWidget);

    // Adding the same library item again is rejected, politely.
    await tester.tap(find.byTooltip('Configure your day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add from library'));
    await tester.pumpAndSettle();
    await tester.tap(sheetEntry('Pranayama'));
    await tester.pumpAndSettle();
    expect(find.text('Pranayama is already in your day.'), findsOneWidget);
  });
}
