/// The onboarding flow: a short, skippable step sequence that
/// collects the user's profile — name and age, goals, habits to
/// change, and the rhythm of their day.
///
/// Used in two modes:
///  * First launch — hosted by the app gate as the home widget,
///    starts with a welcome step, and reports the saved profile
///    through [onComplete] so the gate can swap in the shell.
///  * Edit — pushed as a route from Today's profile button,
///    prefilled with the current profile, titled 'Your profile',
///    and pops with the saved profile as its result.
///
/// Finishing or skipping at any step saves whatever was entered
/// (defaults otherwise) and marks onboarding done: the flow can
/// never trap the user outside the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile.dart';
import 'profile_store.dart';

enum _Step { welcome, about, goals, habits, rhythm }

class OnboardingScreen extends StatefulWidget {
  /// The profile the fields start from (defaults on first launch,
  /// the saved profile in edit mode).
  final UserProfile initial;

  /// Edit mode: no welcome step, 'Your profile' title, pops with
  /// the saved profile instead of calling [onComplete].
  final bool editMode;

  /// First-launch completion callback. When null, finishing pops
  /// the route with the saved [UserProfile] as the result.
  final ValueChanged<UserProfile>? onComplete;

  const OnboardingScreen({
    super.key,
    required this.initial,
    this.editMode = false,
    this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final List<_Step> _steps;
  int _stepIndex = 0;

  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _customGoalController;
  late final TextEditingController _customHabitController;
  String? _ageError;

  /// Selections in the order they were picked; custom entries are
  /// appended to the chip lists beyond the built-in options.
  late final List<String> _selectedGoals;
  late final List<String> _customGoals;
  late final List<String> _selectedHabits;
  late final List<String> _customHabits;

  late TimeOfDay _wake;
  late TimeOfDay _bedtime;

  _Step get _step => _steps[_stepIndex];
  bool get _isLast => _stepIndex == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _steps = widget.editMode
        ? const [_Step.about, _Step.goals, _Step.habits, _Step.rhythm]
        : const [
            _Step.welcome,
            _Step.about,
            _Step.goals,
            _Step.habits,
            _Step.rhythm,
          ];
    _nameController = TextEditingController(text: initial.name);
    _ageController = TextEditingController(
      text: initial.age == null ? '' : '${initial.age}',
    );
    _customGoalController = TextEditingController();
    _customHabitController = TextEditingController();
    _selectedGoals = List<String>.of(initial.goals);
    _customGoals = [
      for (final goal in initial.goals)
        if (!goalOptions.contains(goal)) goal,
    ];
    _selectedHabits = List<String>.of(initial.badHabits);
    _customHabits = [
      for (final habit in initial.badHabits)
        if (!habitOptions.contains(habit)) habit,
    ];
    _wake = _parseTime(initial.wakeTime, const TimeOfDay(hour: 5, minute: 30));
    _bedtime = _parseTime(
      initial.bedtime,
      const TimeOfDay(hour: 20, minute: 30),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _customGoalController.dispose();
    _customHabitController.dispose();
    super.dispose();
  }

  static TimeOfDay _parseTime(String hhmm, TimeOfDay fallback) {
    if (!isValidTimeOfDay(hhmm)) return fallback;
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  // --- Flow control -------------------------------------------------

  bool _validateAge() {
    final text = _ageController.text.trim();
    if (text.isEmpty) {
      setState(() => _ageError = null);
      return true;
    }
    final value = int.tryParse(text);
    if (value == null || value < 5 || value > 120) {
      setState(
        () => _ageError = 'Enter an age between 5 and 120, or leave it blank.',
      );
      return false;
    }
    setState(() => _ageError = null);
    return true;
  }

  void _next() {
    if (_step == _Step.about && !_validateAge()) return;
    if (_isLast) {
      _finish();
    } else {
      setState(() => _stepIndex++);
    }
  }

  void _back() {
    if (_stepIndex > 0) setState(() => _stepIndex--);
  }

  /// The profile as currently entered. An out-of-range age is
  /// dropped rather than saved (stepping Next validates strictly;
  /// Skip stays lenient so it can never wedge the flow).
  UserProfile _enteredProfile() {
    final ageText = _ageController.text.trim();
    final parsed = int.tryParse(ageText);
    return UserProfile(
      name: _nameController.text.trim(),
      age: parsed != null && parsed >= 5 && parsed <= 120 ? parsed : null,
      goals: List<String>.of(_selectedGoals),
      badHabits: List<String>.of(_selectedHabits),
      wakeTime: _formatTime(_wake),
      bedtime: _formatTime(_bedtime),
    );
  }

  Future<void> _finish() async {
    final profile = _enteredProfile();
    await ProfileStore.saveProfile(profile);
    await ProfileStore.markOnboarded();
    if (!mounted) return;
    final onComplete = widget.onComplete;
    if (onComplete != null) {
      onComplete(profile);
    } else {
      Navigator.of(context).pop(profile);
    }
  }

  // --- Build ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.editMode
          ? AppBar(title: const Text('Your profile'))
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: switch (_step) {
                  _Step.welcome => _buildWelcome(theme),
                  _Step.about => _buildAbout(theme),
                  _Step.goals => _buildGoals(theme),
                  _Step.habits => _buildHabits(theme),
                  _Step.rhythm => _buildRhythm(theme),
                },
              ),
            ),
            _buildNavBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBar(ThemeData theme) {
    final primaryLabel = switch ((_step, _isLast)) {
      (_Step.welcome, _) => 'Begin',
      (_, true) => 'Done',
      _ => 'Next',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          if (_stepIndex > 0)
            TextButton(onPressed: _back, child: const Text('Back')),
          const Spacer(),
          TextButton(onPressed: _finish, child: const Text('Skip')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _next, child: Text(primaryLabel)),
        ],
      ),
    );
  }

  Widget _stepHeading(ThemeData theme, String title, String line) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          line,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWelcome(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/images/meditation_image.jpg',
            height: 240,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Calm n Healthy',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "The best \$5 you'll ever spend",
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'A minute to set up your profile — your goals, the '
          'habits you want to change, and the rhythm of your day. '
          'Everything stays on this phone.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildAbout(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeading(
          theme,
          'About you',
          'Just a name to greet you by, and your age so the '
              'practices fit where you are in life.',
        ),
        TextField(
          key: const Key('profile-name-field'),
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('profile-age-field'),
          controller: _ageController,
          decoration: InputDecoration(
            labelText: 'Age',
            border: const OutlineInputBorder(),
            errorText: _ageError,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _buildChipPicker({
    required ThemeData theme,
    required String title,
    required String line,
    required List<String> options,
    required List<String> customs,
    required List<String> selected,
    required TextEditingController customController,
    required Key customFieldKey,
    required String customHint,
  }) {
    void toggle(String value, bool on) {
      setState(() {
        if (on) {
          if (!selected.contains(value)) selected.add(value);
        } else {
          selected.remove(value);
        }
      });
    }

    void addCustom() {
      final value = customController.text.trim();
      if (value.isEmpty) return;
      setState(() {
        if (!options.contains(value) && !customs.contains(value)) {
          customs.add(value);
        }
        if (!selected.contains(value)) selected.add(value);
        customController.clear();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeading(theme, title, line),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in [...options, ...customs])
              FilterChip(
                label: Text(option),
                selected: selected.contains(option),
                onSelected: (on) => toggle(option, on),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: customFieldKey,
                controller: customController,
                decoration: InputDecoration(
                  labelText: 'Add your own',
                  hintText: customHint,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => addCustom(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: addCustom,
              icon: const Icon(Icons.add),
              tooltip: 'Add your own',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoals(ThemeData theme) {
    return _buildChipPicker(
      theme: theme,
      title: 'Your goals',
      line:
          'Pick any that fit — these shape what the app '
          'suggests and celebrates.',
      options: goalOptions,
      customs: _customGoals,
      selected: _selectedGoals,
      customController: _customGoalController,
      customFieldKey: const Key('custom-goal-field'),
      customHint: 'e.g. Run a 5k',
    );
  }

  Widget _buildHabits(ThemeData theme) {
    return _buildChipPicker(
      theme: theme,
      title: 'Habits to change',
      line:
          'No judgement — just the ones you want the app to '
          'help you pause before.',
      options: habitOptions,
      customs: _customHabits,
      selected: _selectedHabits,
      customController: _customHabitController,
      customFieldKey: const Key('custom-habit-field'),
      customHint: 'e.g. Late-night snacking',
    );
  }

  Widget _buildRhythm(ThemeData theme) {
    Future<void> pickWake() async {
      final picked = await showTimePicker(context: context, initialTime: _wake);
      if (picked != null && mounted) setState(() => _wake = picked);
    }

    Future<void> pickBedtime() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: _bedtime,
      );
      if (picked != null && mounted) setState(() => _bedtime = picked);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeading(
          theme,
          'Your rhythm',
          'When your day starts and winds down. Your plan and '
              'reminders will follow these times.',
        ),
        ListTile(
          leading: const Icon(Icons.wb_sunny_outlined),
          title: const Text('Wake up'),
          trailing: Text(
            _formatTime(_wake),
            style: theme.textTheme.titleMedium,
          ),
          onTap: pickWake,
        ),
        ListTile(
          leading: const Icon(Icons.nightlight_outlined),
          title: const Text('Bedtime'),
          trailing: Text(
            _formatTime(_bedtime),
            style: theme.textTheme.titleMedium,
          ),
          onTap: pickBedtime,
        ),
      ],
    );
  }
}
