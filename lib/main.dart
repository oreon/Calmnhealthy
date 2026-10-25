import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_tab.dart';
import 'log_tab.dart';
import 'meditate_tab.dart';
import 'onboarding_screen.dart';
import 'profile.dart';
import 'profile_store.dart';
import 'today_screen.dart';

/// Deep teal brand seed (matches the Buddha icon background) and the
/// warm gold used for points/highlights.
const Color brandTeal = Color(0xFF00484D);
const Color brandGold = Color(0xFFC9A227);

/// SharedPreferences key the guarded startup writes the last caught
/// error to, so a failure is recorded instead of taking the app down.
const String lastErrorKey = 'cnh.last_error';

Future<void> _recordError(Object error, StackTrace stack) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      lastErrorKey,
      '${DateTime.now().toIso8601String()}\n$error\n$stack',
    );
  } catch (_) {
    // Error recording is best-effort; it must never crash either.
  }
}

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        _recordError(details.exception, details.stack ?? StackTrace.empty);
      };
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        _recordError(error, stack);
        return true; // Recorded, not fatal.
      };
      runApp(const CalmNHealthyApp());
    },
    (error, stack) {
      _recordError(error, stack);
    },
  );
}

class CalmNHealthyApp extends StatelessWidget {
  const CalmNHealthyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: brandTeal,
          brightness: Brightness.dark,
        ).copyWith(
          secondary: brandGold,
          tertiary: brandGold,
          onSecondary: Colors.black,
        );
    return MaterialApp(
      title: 'Calm n Healthy',
      theme: ThemeData(useMaterial3: true, colorScheme: colorScheme),
      home: const AppGate(),
    );
  }
}

/// First-launch gate: shows the onboarding flow until it has been
/// finished or skipped, then the shell. Startup state loads behind
/// a brief brand splash, and any load failure fails OPEN — the
/// shell with a default profile — so the gate can never lock the
/// user out of the app.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool _loading = true;
  bool _onboarded = false;
  UserProfile _profile = UserProfile.defaults;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var onboarded = true; // Fail open if anything goes wrong.
    var profile = UserProfile.defaults;
    try {
      profile = await ProfileStore.loadProfile();
      onboarded = await ProfileStore.isOnboarded();
    } catch (_) {
      onboarded = true;
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _onboarded = onboarded;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final theme = Theme.of(context);
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Calm n Healthy',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    if (!_onboarded) {
      return OnboardingScreen(
        initial: _profile,
        onComplete: (saved) => setState(() {
          _profile = saved;
          _onboarded = true;
        }),
      );
    }
    return const HomeShell();
  }
}

/// Bottom-navigation shell with the five tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const List<Widget> _tabs = [
    TodayScreen(),
    ExerciseTab(),
    MeditateTab(),
    PlaceholderTab(
      title: 'Diet',
      icon: Icons.restaurant,
      line:
          'Food snapshots and the eating window arrive in the next milestones.',
    ),
    LogTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Exercise',
          ),
          NavigationDestination(
            icon: Icon(Icons.self_improvement_outlined),
            selectedIcon: Icon(Icons.self_improvement),
            label: 'Meditate',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Diet',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Log',
          ),
        ],
      ),
    );
  }
}

/// Honest placeholder for a tab whose features arrive in later
/// milestones: brand header, the tab name, and one truthful line.
class PlaceholderTab extends StatelessWidget {
  final String title;
  final IconData icon;
  final String line;

  const PlaceholderTab({
    super.key,
    required this.title,
    required this.icon,
    required this.line,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Calm n Healthy',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 56, color: theme.colorScheme.secondary),
                  const SizedBox(height: 16),
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    line,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
