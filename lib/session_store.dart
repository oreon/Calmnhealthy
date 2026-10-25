/// SharedPreferences persistence for guided sessions: the same-day
/// draft, once-only points awards, and the completion log.
///
/// Storage keys are `cnh.`-prefixed and the lifetime-points key
/// ('cnh.lifetime_points') is shared with the Today tab, so a point
/// earned anywhere in the app lands in the same total.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_engine.dart';

/// One completed-session record for the Log tab.
class SessionLogEntry {
  /// ISO-8601 completion timestamp.
  final String timestamp;

  /// The practice's display title, e.g. 'Upper Body'.
  final String kind;

  /// The practice id, e.g. 'strength-upper'.
  final String practiceId;

  /// Actively practiced seconds (pauses/rests/skips excluded).
  final int activeSeconds;

  /// Points this completion awarded.
  final int points;

  /// One of the five feeling faces, or '' when not chosen.
  final String feeling;

  /// Optional free-text reflection, '' when not written.
  final String reflection;

  const SessionLogEntry({
    required this.timestamp,
    required this.kind,
    required this.practiceId,
    required this.activeSeconds,
    required this.points,
    this.feeling = '',
    this.reflection = '',
  });

  /// The 'yyyy-MM-dd' day this entry belongs to.
  String get dateKey => timestamp.substring(0, 10);

  /// Whole active minutes, for compact display.
  int get activeMinutes => activeSeconds ~/ 60;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'kind': kind,
    'practice_id': practiceId,
    'active_seconds': activeSeconds,
    'points': points,
    'feeling': feeling,
    'reflection': reflection,
  };

  static SessionLogEntry? tryFromJson(Map<String, dynamic> json) {
    final timestamp = json['timestamp'] as String?;
    final kind = json['kind'] as String?;
    if (timestamp == null || kind == null) return null;
    return SessionLogEntry(
      timestamp: timestamp,
      kind: kind,
      practiceId: json['practice_id'] as String? ?? '',
      activeSeconds: (json['active_seconds'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      feeling: json['feeling'] as String? ?? '',
      reflection: json['reflection'] as String? ?? '',
    );
  }
}

/// Reads and writes the session records.
class SessionStore {
  /// Shared with the Today tab — do not rename.
  static const String lifetimePointsKey = 'cnh.lifetime_points';
  static const String draftKey = 'cnh.session_draft';
  static const String awardedKey = 'cnh.awarded_sessions';
  static const String logKey = 'cnh.session_log';

  /// Bumped whenever session records change, so open tabs (e.g. the
  /// Log) can refresh themselves.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void _bump() => changes.value++;

  static Future<int> lifetimePoints() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(lifetimePointsKey) ?? 0;
  }

  // --- Draft -------------------------------------------------------

  static Future<void> saveDraft(SessionDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(draftKey, jsonEncode(draft.toJson()));
    _bump();
  }

  /// The saved draft, or null when there is none, it is unreadable,
  /// or it belongs to a different day than [todayKey] ('yyyy-MM-dd').
  /// A stale draft is discarded so it cannot resurface tomorrow.
  static Future<SessionDraft?> loadDraft(String todayKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(draftKey);
    if (raw == null) return null;
    SessionDraft? draft;
    try {
      draft = SessionDraft.tryFromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      draft = null;
    }
    if (draft == null || !draft.isForDate(todayKey)) {
      await prefs.remove(draftKey);
      return null;
    }
    return draft;
  }

  static Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(draftKey);
    _bump();
  }

  // --- Completion --------------------------------------------------

  /// Records a finished session exactly once per [sessionKey]:
  /// awards its points into the shared lifetime total, appends the
  /// log entry, and clears the matching draft. Returns the points
  /// actually awarded (0 when this session key was already recorded).
  static Future<int> completeSession({
    required String sessionKey,
    required SessionLogEntry entry,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final awarded = prefs.getStringList(awardedKey) ?? <String>[];
    if (awarded.contains(sessionKey)) return 0;
    awarded.add(sessionKey);
    await prefs.setStringList(awardedKey, awarded);

    final lifetime = prefs.getInt(lifetimePointsKey) ?? 0;
    await prefs.setInt(lifetimePointsKey, lifetime + entry.points);

    final log = prefs.getStringList(logKey) ?? <String>[];
    log.add(jsonEncode(entry.toJson()));
    await prefs.setStringList(logKey, log);

    final draft = await loadDraft(entry.dateKey);
    if (draft != null && draft.sessionKey == sessionKey) {
      await prefs.remove(draftKey);
    }
    _bump();
    return entry.points;
  }

  /// All log entries for one 'yyyy-MM-dd' day, oldest first.
  static Future<List<SessionLogEntry>> logForDate(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(logKey) ?? <String>[];
    final entries = <SessionLogEntry>[];
    for (final item in raw) {
      try {
        final entry = SessionLogEntry.tryFromJson(
          jsonDecode(item) as Map<String, dynamic>,
        );
        if (entry != null && entry.dateKey == dateKey) entries.add(entry);
      } catch (_) {
        // Skip unreadable rows rather than breaking the whole log.
      }
    }
    return entries;
  }
}
