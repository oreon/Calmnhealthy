import 'dart:convert';

import 'package:calm_n_healthy/session_engine.dart';
import 'package:calm_n_healthy/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SessionLogEntry _entry({
  required String timestamp,
  String kind = 'Yoga',
  String practiceId = 'yoga',
  int activeSeconds = 120,
  int points = 4,
  String feeling = '',
  String reflection = '',
}) {
  return SessionLogEntry(
    timestamp: timestamp,
    kind: kind,
    practiceId: practiceId,
    activeSeconds: activeSeconds,
    points: points,
    feeling: feeling,
    reflection: reflection,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SessionStore.debugResetCache();
  });

  group('completeSession', () {
    test('appends a log row, awards points, and keeps older rows', () async {
      final first = await SessionStore.completeSession(
        sessionKey: 'yoga:1',
        entry: _entry(timestamp: '2026-10-27T08:00:00.000', points: 4),
      );
      final second = await SessionStore.completeSession(
        sessionKey: 'box:1',
        entry: _entry(
          timestamp: '2026-10-28T09:05:00.000',
          kind: 'Box breathing',
          practiceId: 'box-breathing',
          activeSeconds: 60,
          points: 2,
          feeling: '🙂',
          reflection: 'steady',
        ),
      );

      expect(first, 4);
      expect(second, 2);
      expect(await SessionStore.lifetimePoints(), 6);

      final older = await SessionStore.logForDate('2026-10-27');
      expect(older, hasLength(1));
      expect(older.single.kind, 'Yoga');

      final today = await SessionStore.logForDate('2026-10-28');
      expect(today, hasLength(1));
      expect(today.single.kind, 'Box breathing');
      expect(today.single.feeling, '🙂');
      expect(today.single.reflection, 'steady');
      expect(today.single.activeMinutes, 1);
      expect(today.single.points, 2);
    });

    test('same-day rows stay oldest first', () async {
      await SessionStore.completeSession(
        sessionKey: 'a',
        entry: _entry(timestamp: '2026-10-28T08:00:00.000', kind: 'First'),
      );
      await SessionStore.completeSession(
        sessionKey: 'b',
        entry: _entry(timestamp: '2026-10-28T09:00:00.000', kind: 'Second'),
      );

      final entries = await SessionStore.logForDate('2026-10-28');
      expect(entries.map((entry) => entry.kind).toList(), ['First', 'Second']);
    });

    test(
      'a repeated session key awards nothing and does not duplicate',
      () async {
        final entry = _entry(timestamp: '2026-10-28T08:00:00.000', points: 6);
        expect(
          await SessionStore.completeSession(sessionKey: 'once', entry: entry),
          6,
        );
        expect(
          await SessionStore.completeSession(sessionKey: 'once', entry: entry),
          0,
        );

        expect(await SessionStore.lifetimePoints(), 6);
        expect(await SessionStore.logForDate('2026-10-28'), hasLength(1));
      },
    );

    test(
      'clears only the draft that belongs to the finished session',
      () async {
        await SessionStore.saveDraft(
          const SessionDraft(
            practiceId: 'yoga',
            sessionKey: 'yoga:1',
            date: '2026-10-28',
          ),
        );
        await SessionStore.completeSession(
          sessionKey: 'other',
          entry: _entry(timestamp: '2026-10-28T08:00:00.000'),
        );
        expect(
          (await SessionStore.loadDraft('2026-10-28'))?.sessionKey,
          'yoga:1',
        );

        await SessionStore.completeSession(
          sessionKey: 'yoga:1',
          entry: _entry(
            timestamp: '2026-10-28T08:30:00.000',
            kind: 'Yoga again',
          ),
        );
        expect(await SessionStore.loadDraft('2026-10-28'), isNull);
      },
    );
  });

  group('damaged rows', () {
    test(
      'skips them, counts them, and leaves every stored row in place',
      () async {
        final valid = jsonEncode(
          _entry(timestamp: '2026-10-28T10:00:00.000', kind: 'Kept').toJson(),
        );
        final stored = <String>[
          '{not json',
          jsonEncode({'kind': 'No timestamp'}),
          jsonEncode({'timestamp': 'short', 'kind': 'Too short'}),
          jsonEncode({
            'timestamp': '2026-10-28T11:00:00.000',
            'kind': 'Bad points',
            'points': 'lots',
          }),
          '[]',
          valid,
          jsonEncode({
            'timestamp': '2026-10-27T07:00:00.000',
            'kind': 'Other day',
          }),
        ];
        SharedPreferences.setMockInitialValues({SessionStore.logKey: stored});
        SessionStore.debugResetCache();

        final today = await SessionStore.logForDate('2026-10-28');
        final yesterday = await SessionStore.logForDate('2026-10-27');

        expect(today.map((entry) => entry.kind).toList(), ['Kept']);
        expect(yesterday.map((entry) => entry.kind).toList(), ['Other day']);
        expect(await SessionStore.unreadableLogEntries(), 5);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(SessionStore.logKey), stored);
      },
    );
  });

  group('cache', () {
    test('decodes once until a new completion invalidates it', () async {
      await SessionStore.completeSession(
        sessionKey: 'a',
        entry: _entry(timestamp: '2026-10-28T08:00:00.000', kind: 'Saved'),
      );
      SessionStore.debugDecodeCount = 0;

      expect(
        (await SessionStore.logForDate('2026-10-28')).single.kind,
        'Saved',
      );
      expect(await SessionStore.logForDate('2026-10-27'), isEmpty);
      expect(await SessionStore.unreadableLogEntries(), 0);
      expect(SessionStore.debugDecodeCount, 1);

      // A write that bypasses SessionStore must not be observed while
      // the cache is still valid — the store invalidates on its own
      // writes, not on every read.
      final prefs = await SharedPreferences.getInstance();
      final raw = List<String>.of(prefs.getStringList(SessionStore.logKey)!);
      raw.add(
        jsonEncode(
          _entry(
            timestamp: '2026-10-28T12:00:00.000',
            kind: 'Sneaked',
          ).toJson(),
        ),
      );
      await prefs.setStringList(SessionStore.logKey, raw);

      expect((await SessionStore.logForDate('2026-10-28')).map((e) => e.kind), [
        'Saved',
      ]);
      expect(SessionStore.debugDecodeCount, 1);

      await SessionStore.completeSession(
        sessionKey: 'b',
        entry: _entry(timestamp: '2026-10-28T13:00:00.000', kind: 'Logged'),
      );
      final kinds = (await SessionStore.logForDate(
        '2026-10-28',
      )).map((entry) => entry.kind).toList();
      expect(kinds, ['Saved', 'Sneaked', 'Logged']);
      expect(SessionStore.debugDecodeCount, 2);
    });
  });
}
