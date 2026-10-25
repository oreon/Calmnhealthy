/// Pure-Dart model for the user's onboarding profile: who they
/// are, what they're working toward, the habits they want to
/// change, and the rhythm of their day.
///
/// No Flutter imports on purpose — everything here is
/// unit-testable without widgets.
library;

import 'dart:convert';

/// Goal choices offered as chips in onboarding. A user's saved
/// goals may also hold custom entries beyond this list.
const List<String> goalOptions = [
  'Sleep better',
  'More energy',
  'Build strength',
  'Meditate daily',
  'Eat mindfully',
  'Less stress',
  'Breathe better',
];

/// Bad-habit choices offered as chips in onboarding. A user's
/// saved habits may also hold custom entries beyond this list.
const List<String> habitOptions = [
  'Doom scrolling',
  'Mindless eating',
  'Late nights',
  'Too much caffeine',
  'Skipping practice',
  'Sugar',
];

/// Time-of-day greeting for an hour of day (0–23): morning before
/// noon, afternoon until 18:00, evening from 18:00.
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// Whether a 'HH:mm' string is a usable time of day.
bool isValidTimeOfDay(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return false;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  return hour != null &&
      minute != null &&
      hour >= 0 &&
      hour < 24 &&
      minute >= 0 &&
      minute < 60;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String) item,
  ];
}

/// The user's profile, collected by the onboarding flow and
/// editable later from Today. Everything is stored on-device only.
class UserProfile {
  /// Display name, '' when not given.
  final String name;

  /// Age in years, null when not given.
  final int? age;

  /// Selected goals (chips and/or custom entries).
  final List<String> goals;

  /// Selected habits to change (chips and/or custom entries).
  final List<String> badHabits;

  /// Wake time, 'HH:mm' in 24-hour form.
  final String wakeTime;

  /// Bedtime, 'HH:mm' in 24-hour form.
  final String bedtime;

  const UserProfile({
    this.name = '',
    this.age,
    this.goals = const [],
    this.badHabits = const [],
    this.wakeTime = '05:30',
    this.bedtime = '20:30',
  });

  /// The empty profile: no answers given yet.
  static const UserProfile defaults = UserProfile();

  /// The first word of the trimmed name, '' when there is none.
  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  UserProfile copyWith({
    String? name,
    int? age,
    List<String>? goals,
    List<String>? badHabits,
    String? wakeTime,
    String? bedtime,
  }) => UserProfile(
    name: name ?? this.name,
    age: age ?? this.age,
    goals: goals ?? this.goals,
    badHabits: badHabits ?? this.badHabits,
    wakeTime: wakeTime ?? this.wakeTime,
    bedtime: bedtime ?? this.bedtime,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'goals': goals,
    'badHabits': badHabits,
    'wakeTime': wakeTime,
    'bedtime': bedtime,
  };

  /// Parses a profile, tolerating partial or mistyped data: every
  /// missing or unusable field falls back to its default, so a
  /// half-written profile still yields a sane [UserProfile].
  static UserProfile fromJson(Map<String, dynamic> json) {
    final age = json['age'];
    final wakeTime = json['wakeTime'] as String?;
    final bedtime = json['bedtime'] as String?;
    return UserProfile(
      name: json['name'] as String? ?? '',
      age: age is num ? age.toInt() : null,
      goals: _stringList(json['goals']),
      badHabits: _stringList(json['badHabits']),
      wakeTime: wakeTime != null && isValidTimeOfDay(wakeTime)
          ? wakeTime
          : '05:30',
      bedtime: bedtime != null && isValidTimeOfDay(bedtime) ? bedtime : '20:30',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.name == name &&
      other.age == age &&
      _listEquals(other.goals, goals) &&
      _listEquals(other.badHabits, badHabits) &&
      other.wakeTime == wakeTime &&
      other.bedtime == bedtime;

  @override
  int get hashCode => Object.hash(
    name,
    age,
    Object.hashAll(goals),
    Object.hashAll(badHabits),
    wakeTime,
    bedtime,
  );
}

/// Serializes a profile for storage.
String encodeProfile(UserProfile profile) => jsonEncode(profile.toJson());

/// Parses a stored profile, or null when it is unreadable —
/// callers fall back to [UserProfile.defaults] rather than
/// blocking the app on a corrupt value.
UserProfile? decodeProfile(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return UserProfile.fromJson(decoded);
  } catch (_) {
    return null;
  }
}
