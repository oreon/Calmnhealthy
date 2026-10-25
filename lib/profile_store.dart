/// SharedPreferences persistence for the onboarding profile and
/// the onboarded flag.
///
/// Reading the profile must never block app entry: any failure —
/// missing value, corrupt JSON, storage error — resolves to
/// [UserProfile.defaults], and an unreadable onboarded flag is
/// treated as onboarded, so the shell always opens.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'profile.dart';

class ProfileStore {
  /// The user's profile as JSON (see [encodeProfile]).
  static const String profileKey = 'cnh.profile';

  /// True once the user has finished or skipped onboarding.
  static const String onboardedKey = 'cnh.onboarded';

  /// The saved profile, or [UserProfile.defaults] when there is
  /// none or it cannot be read.
  static Future<UserProfile> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(profileKey);
      if (raw == null) return UserProfile.defaults;
      return decodeProfile(raw) ?? UserProfile.defaults;
    } catch (_) {
      return UserProfile.defaults;
    }
  }

  /// Persists the profile.
  static Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(profileKey, encodeProfile(profile));
  }

  /// Whether onboarding has been completed or skipped. A storage
  /// error counts as onboarded — the flow must never trap the
  /// user outside their own app.
  static Future<bool> isOnboarded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(onboardedKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  /// Records that onboarding is done (finished or skipped).
  static Future<void> markOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardedKey, true);
  }
}
