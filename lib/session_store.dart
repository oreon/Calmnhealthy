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
  ///
  /// Empty when [timestamp] is too short to hold a date. Stored rows
  /// that fail [_hasDatePrefix] never become entries, so a normal
  /// log row always has a 10-character date here.
  String get dateKey =>
      timestamp.length >= 10 ? timestamp.substring(0, 10) : '';

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

  /// Decodes one stored object. Returns null when the row is damaged
  /// (missing the required strings, a timestamp that is not a calendar
  /// day, or a field of the wrong JSON type) so the caller can count
  /// it without dropping the neighbouring rows.
  static SessionLogEntry? tryFromJson(Map<String, dynamic> json) {
    final timestamp = json['timestamp'];
    final kind = json['kind'];
    if (timestamp is! String || kind is! String) return null;
    if (!_hasDatePrefix(timestamp)) return null;
    final practiceId = _optionalString(json['practice_id']);
    final feeling = _optionalString(json['feeling']);
    final reflection = _optionalString(json['reflection']);
    final activeSeconds = _optionalInt(json['active_seconds']);
    final points = _optionalInt(json['points']);
    if (practiceId == null ||
        feeling == null ||
        reflection == null ||
        activeSeconds == null ||
        points == null) {
      return null;
    }
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

  /// True when [timestamp] begins with a 'yyyy-MM-dd' calendar day.
  static bool _hasDatePrefix(String timestamp) {
    if (timestamp.length < 10) return false;
    for (var i = 0; i < 10; i++) {
      final code = timestamp.codeUnitAt(i);
      final dashSlot = i == 4 || i == 7;
      final isDigit = code >= 0x30 && code <= 0x39;
      if (dashSlot) {
        if (code != 0x2d) return false;
      } else if (!isDigit) {
        return false;
      }
    }
    return true;
  }

  /// Missing optional strings default to ''. A present non-string is
  /// damage, reported as null so the whole row is skipped.
  static String? _optionalString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return null;
  }

  /// Missing optional numbers default to 0. A present non-number is
  /// damage, reported as null so the whole row is skipped.
  static int? _optionalInt(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return null;
  }
}

/// Reads and writes the session records.
///
/// The completion log is decoded once and kept in memory until
/// [completeSession] writes a new row. Reading another day, or
/// reading the same day again, does not parse the stored JSON a
/// second time. Damaged rows stay in storage; they are counted and
/// reported, never deleted.
class SessionStore {
  /// Shared with the Today tab — do not rename.
  static const String lifetimePointsKey = 'cnh.lifetime_points';
  static const String draftKey = 'cnh.session_draft';
  static const String awardedKey = 'cnh.awarded_sessions';
  static const String logKey = 'cnh.session_log';

  /// Bumped whenever session records change, so open tabs (e.g. the
  /// Log) can refresh themselves.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static _DecodedLog? _cachedLog;
  static int _logGeneration = 0;

  /// How many times the stored log has actually been JSON-decoded.
  /// Tests use this to prove repeat reads hit the memory cache.
  @visibleForTesting
  static int debugDecodeCount = 0;

  /// Drops the in-memory log so the next read decodes storage again.
  /// Production code invalidates itself inside [completeSession];
  /// tests call this between cases that replace SharedPreferences.
  @visibleForTesting
  static void debugResetCache() {
    _logGeneration++;
    _cachedLog = null;
    debugDecodeCount = 0;
  }

  static void _invalidateLogCache() {
    _logGeneration++;
    _cachedLog = null;
  }

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

    // Copy first: getStringList can hand back a live view of the
    // stored list, and the previous rows (including damaged ones)
    // must be written back unchanged.
    final log = List<String>.of(
      prefs.getStringList(logKey) ?? const <String>[],
    );
    log.add(jsonEncode(entry.toJson()));
    await prefs.setStringList(logKey, log);
    _invalidateLogCache();

    final draft = await loadDraft(entry.dateKey);
    if (draft != null && draft.sessionKey == sessionKey) {
      await prefs.remove(draftKey);
    }
    _bump();
    return entry.points;
  }

  /// All readable log entries for one 'yyyy-MM-dd' day, oldest first.
  ///
  /// Damaged rows are left in storage. They are not part of this
  /// list; [unreadableLogEntries] counts them.
  static Future<List<SessionLogEntry>> logForDate(String dateKey) async {
    final decoded = await _decodedLog();
    return [
      for (final entry in decoded.entries)
        if (entry.dateKey == dateKey) entry,
    ];
  }

  /// How many stored rows could not be decoded the last time the log
  /// was read. Valid rows are never removed to "fix" this count.
  static Future<int> unreadableLogEntries() async {
    final decoded = await _decodedLog();
    return decoded.unreadableCount;
  }

  static Future<_DecodedLog> _decodedLog() async {
    final cached = _cachedLog;
    if (cached != null) return cached;
    final generation = _logGeneration;
    final prefs = await SharedPreferences.getInstance();
    // A completion may have landed while we waited for prefs. Don't
    // cache the stale read; load again.
    if (generation != _logGeneration) return _decodedLog();
    final raw = prefs.getStringList(logKey) ?? const <String>[];
    if (generation != _logGeneration) return _decodedLog();
    final decoded = _decodeLog(raw);
    if (generation != _logGeneration) return _decodedLog();
    _cachedLog = decoded;
    return decoded;
  }

  static _DecodedLog _decodeLog(List<String> raw) {
    debugDecodeCount++;
    final entries = <SessionLogEntry>[];
    var unreadable = 0;
    for (final item in raw) {
      final entry = _tryDecodeStoredRow(item);
      if (entry == null) {
        unreadable++;
      } else {
        entries.add(entry);
      }
    }
    return _DecodedLog(entries, unreadable);
  }

  /// One stored string to an entry, or null when the row is damaged.
  /// Never throws: a bad row must not fail the rest of the log.
  static SessionLogEntry? _tryDecodeStoredRow(String item) {
    try {
      final decoded = jsonDecode(item);
      if (decoded is! Map) {
        _logUnreadable('expected a JSON object');
        return null;
      }
      final entry = SessionLogEntry.tryFromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (entry == null) {
        _logUnreadable('missing a usable timestamp and kind');
        return null;
      }
      return entry;
    } catch (error) {
      _logUnreadable(error);
      return null;
    }
  }

  static void _logUnreadable(Object reason) {
    if (kDebugMode) {
      debugPrint('SessionStore: skipped unreadable log entry: $reason');
    }
  }
}

class _DecodedLog {
  final List<SessionLogEntry> entries;
  final int unreadableCount;

  const _DecodedLog(this.entries, this.unreadableCount);
}
