import 'dart:convert';

import 'package:calm_n_healthy/log_tab.dart';
import 'package:calm_n_healthy/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _iso(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute).toIso8601String();

String _row({
  required DateTime day,
  required int hour,
  required int minute,
  required String kind,
  int activeSeconds = 120,
  int points = 4,
  String feeling = '',
  String reflection = '',
}) {
  return jsonEncode({
    'timestamp': _iso(day, hour, minute),
    'kind': kind,
    'practice_id': 'yoga',
    'active_seconds': activeSeconds,
    'points': points,
    'feeling': feeling,
    'reflection': reflection,
  });
}

Future<void> _pumpLog(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: LogTab()));
  await tester.pumpAndSettle();
}

IconButton _dayButton(WidgetTester tester, IconData icon) {
  return tester.widget<IconButton>(
    find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SessionStore.debugResetCache();
  });

  testWidgets('empty today explains that nothing is saved yet', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await _pumpLog(tester);

    expect(
      find.textContaining('No completed sessions yet today'),
      findsOneWidget,
    );
    expect(find.textContaining('Today ·'), findsOneWidget);
    expect(_dayButton(tester, Icons.chevron_right).onPressed, isNull);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();

    expect(find.text('No completed sessions on this day.'), findsOneWidget);
    expect(find.text('Back to today'), findsOneWidget);
    expect(
      find.textContaining('No completed sessions yet today'),
      findsNothing,
    );
  });

  testWidgets('shows today\'s entries and hides other days', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateUtils.addDaysToDate(today, -1);
    SharedPreferences.setMockInitialValues({
      SessionStore.logKey: [
        _row(day: yesterday, hour: 7, minute: 15, kind: 'Yesterday yoga'),
        _row(
          day: today,
          hour: 9,
          minute: 5,
          kind: 'Morning sit',
          activeSeconds: 90,
          points: 2,
          feeling: '🙂',
          reflection: 'quiet',
        ),
        _row(day: today, hour: 18, minute: 40, kind: 'Evening sit', points: 6),
      ],
    });

    await _pumpLog(tester);

    expect(find.text('Yesterday yoga'), findsNothing);
    expect(find.text('Morning sit'), findsOneWidget);
    expect(find.text('Evening sit'), findsOneWidget);
    expect(find.textContaining('09:05'), findsOneWidget);
    expect(find.textContaining('1 min practised'), findsOneWidget);
    expect(find.textContaining('quiet'), findsOneWidget);
    expect(find.text('🙂'), findsOneWidget);
    expect(find.text('+2 pts'), findsOneWidget);
    expect(find.text('+6 pts'), findsOneWidget);

    // Newest first.
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title! as Text).data, 'Evening sit');
    expect((tiles.last.title! as Text).data, 'Morning sit');
  });

  testWidgets('previous day shows that day\'s saved sessions', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateUtils.addDaysToDate(today, -1);
    SharedPreferences.setMockInitialValues({
      SessionStore.logKey: [
        _row(day: yesterday, hour: 7, minute: 15, kind: 'Yesterday yoga'),
        _row(day: today, hour: 9, minute: 5, kind: 'Morning sit'),
      ],
    });

    await _pumpLog(tester);
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();

    expect(find.text('Yesterday yoga'), findsOneWidget);
    expect(find.text('Morning sit'), findsNothing);
    expect(find.textContaining('Yesterday ·'), findsOneWidget);

    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();

    expect(find.text('Morning sit'), findsOneWidget);
    expect(find.text('Yesterday yoga'), findsNothing);
    expect(_dayButton(tester, Icons.chevron_right).onPressed, isNull);
  });

  testWidgets('a damaged row is counted and the valid row still shows', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    SharedPreferences.setMockInitialValues({
      SessionStore.logKey: [
        '{not json',
        _row(day: today, hour: 8, minute: 0, kind: 'Kept session'),
      ],
    });

    await _pumpLog(tester);

    expect(find.text('Kept session'), findsOneWidget);
    expect(
      find.text('1 saved entry could not be read. It was left in storage.'),
      findsOneWidget,
    );
  });
}
