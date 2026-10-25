// Tests for the onboarding profile (pass 3 of v2.2.0): the pure
// profile model, its persistence, the first-launch flow, and the
// edit flow from Today's profile button.

import 'package:calm_n_healthy/main.dart';
import 'package:calm_n_healthy/profile.dart';
import 'package:calm_n_healthy/profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UserProfile JSON', () {
    test('full round-trip preserves every field', () {
      const profile = UserProfile(
        name: 'Jagdeep Singh',
        age: 50,
        goals: ['Sleep better', 'Run a 5k'],
        badHabits: ['Doom scrolling'],
        wakeTime: '05:15',
        bedtime: '21:00',
      );
      expect(UserProfile.fromJson(profile.toJson()), profile);
      expect(decodeProfile(encodeProfile(profile)), profile);
    });

    test('empty JSON → defaults', () {
      expect(UserProfile.fromJson({}), UserProfile.defaults);
      expect(UserProfile.defaults.name, '');
      expect(UserProfile.defaults.age, isNull);
      expect(UserProfile.defaults.goals, isEmpty);
      expect(UserProfile.defaults.badHabits, isEmpty);
      expect(UserProfile.defaults.wakeTime, '05:30');
      expect(UserProfile.defaults.bedtime, '20:30');
    });

    test('partial data fills the rest with defaults', () {
      final profile = UserProfile.fromJson({'name': 'Jag'});
      expect(profile.name, 'Jag');
      expect(profile.age, isNull);
      expect(profile.wakeTime, '05:30');
      expect(profile.bedtime, '20:30');
    });

    test('unusable fields fall back instead of breaking', () {
      final profile = UserProfile.fromJson({
        'name': 'Jag',
        'age': 'fifty', // Not a number → null.
        'goals': 'Sleep better', // Not a list → empty.
        'wakeTime': '25:99', // Not a time → default.
        'bedtime': '20:45',
      });
      expect(profile.age, isNull);
      expect(profile.goals, isEmpty);
      expect(profile.wakeTime, '05:30');
      expect(profile.bedtime, '20:45');
    });

    test('unreadable stored values decode to null', () {
      expect(decodeProfile('not json'), isNull);
      expect(decodeProfile('[]'), isNull);
      expect(decodeProfile('42'), isNull);
    });

    test('firstName is the first word of the trimmed name', () {
      expect(const UserProfile(name: 'Jagdeep Singh').firstName, 'Jagdeep');
      expect(const UserProfile(name: '  Jag  ').firstName, 'Jag');
      expect(const UserProfile().firstName, '');
    });
  });

  group('greetingForHour', () {
    test('morning / afternoon / evening boundaries', () {
      expect(greetingForHour(0), 'Good morning');
      expect(greetingForHour(11), 'Good morning');
      expect(greetingForHour(12), 'Good afternoon');
      expect(greetingForHour(17), 'Good afternoon');
      expect(greetingForHour(18), 'Good evening');
      expect(greetingForHour(23), 'Good evening');
    });
  });

  group('ProfileStore persistence', () {
    test('nothing saved → defaults and not onboarded', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ProfileStore.loadProfile(), UserProfile.defaults);
      expect(await ProfileStore.isOnboarded(), isFalse);
    });

    test('corrupt profile → defaults, never an error', () async {
      SharedPreferences.setMockInitialValues({
        ProfileStore.profileKey: 'not json',
      });
      expect(await ProfileStore.loadProfile(), UserProfile.defaults);
    });

    test('save/load round-trip and the onboarded flag', () async {
      SharedPreferences.setMockInitialValues({});
      const profile = UserProfile(name: 'Jag', goals: ['Less stress']);
      await ProfileStore.saveProfile(profile);
      await ProfileStore.markOnboarded();
      expect(await ProfileStore.loadProfile(), profile);
      expect(await ProfileStore.isOnboarded(), isTrue);
    });
  });

  group('Onboarding widget flow', () {
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Finder greetingFor(String firstName) => find.byWidgetPredicate(
      (widget) =>
          widget is Text && (widget.data ?? '').endsWith(', $firstName'),
    );

    testWidgets('first launch: onboarding runs, then Today greets by name', (
      tester,
    ) async {
      useTallViewport(tester);
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const CalmNHealthyApp());
      await tester.pumpAndSettle();

      // Welcome step.
      expect(find.textContaining("you'll ever spend"), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);

      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();

      // About you: name + age.
      expect(find.text('About you'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('profile-name-field')),
        'Jagdeep Singh',
      );
      await tester.enterText(find.byKey(const Key('profile-age-field')), '50');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Goals: pick a built-in chip.
      expect(find.text('Your goals'), findsOneWidget);
      await tester.tap(find.text('Sleep better'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Habits: leave unselected, move on.
      expect(find.text('Habits to change'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Rhythm: defaults are fine; finish.
      expect(find.text('Your rhythm'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The shell is up and Today greets by first name.
      expect(find.text('Water'), findsOneWidget);
      expect(greetingFor('Jagdeep'), findsOneWidget);

      // Everything was saved and onboarding is marked done.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ProfileStore.onboardedKey), isTrue);
      final saved = decodeProfile(prefs.getString(ProfileStore.profileKey)!);
      expect(saved, isNotNull);
      expect(saved!.name, 'Jagdeep Singh');
      expect(saved.age, 50);
      expect(saved.goals, ['Sleep better']);
      expect(saved.wakeTime, '05:30');
      expect(saved.bedtime, '20:30');
    });

    testWidgets('onboarded → straight to the shell, no onboarding', (
      tester,
    ) async {
      useTallViewport(tester);
      SharedPreferences.setMockInitialValues({'cnh.onboarded': true});

      await tester.pumpWidget(const CalmNHealthyApp());
      await tester.pumpAndSettle();

      expect(find.text('Water'), findsOneWidget);
      expect(find.text('Begin'), findsNothing);
      expect(find.byTooltip('Your profile'), findsOneWidget);
    });

    testWidgets('edit flow from Today saves a changed selection', (
      tester,
    ) async {
      useTallViewport(tester);
      SharedPreferences.setMockInitialValues({
        'cnh.onboarded': true,
        ProfileStore.profileKey: encodeProfile(
          const UserProfile(name: 'Jagdeep Singh', goals: ['Sleep better']),
        ),
      });

      await tester.pumpWidget(const CalmNHealthyApp());
      await tester.pumpAndSettle();
      expect(greetingFor('Jagdeep'), findsOneWidget);

      // Open the profile in edit mode.
      await tester.tap(find.byTooltip('Your profile'));
      await tester.pumpAndSettle();
      expect(find.text('Your profile'), findsOneWidget); // AppBar title.
      expect(find.text('Begin'), findsNothing); // No welcome step.
      final nameField = tester.widget<TextField>(
        find.byKey(const Key('profile-name-field')),
      );
      expect(nameField.controller!.text, 'Jagdeep Singh');

      // About → Goals: 'Sleep better' starts selected; add another.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final sleepChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Sleep better'),
      );
      expect(sleepChip.selected, isTrue);
      await tester.tap(find.text('More energy'));
      await tester.pumpAndSettle();

      // Habits → Rhythm → Done.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Back on Today; the saved profile carries both goals.
      expect(find.text('Water'), findsOneWidget);
      expect(greetingFor('Jagdeep'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final saved = decodeProfile(prefs.getString(ProfileStore.profileKey)!);
      expect(saved, isNotNull);
      expect(saved!.name, 'Jagdeep Singh');
      expect(saved.goals, containsAll(['Sleep better', 'More energy']));
    });

    testWidgets('skip from the welcome step still marks onboarded', (
      tester,
    ) async {
      useTallViewport(tester);
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const CalmNHealthyApp());
      await tester.pumpAndSettle();
      expect(find.text('Begin'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Water'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ProfileStore.onboardedKey), isTrue);
      expect(
        decodeProfile(prefs.getString(ProfileStore.profileKey) ?? ''),
        UserProfile.defaults,
      );
    });
  });
}
