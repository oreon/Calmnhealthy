/// Pure-Dart catalog of guided practices for the Calm n Healthy v2
/// rewrite.
///
/// Content provenance (read from the old app's content files, then
/// re-expressed here in one data-driven shape — no old code copied):
///  * Upper body list, 45 s work / 15 s rest / 3 sets — the old
///    UpperBodyWorkoutScreen definition.
///  * Lower body list — the old LowerBodyWorkoutScreen definition in
///    `lowerbody_strength.dart` (same 45/15/3 scheme).
///  * Yoga poses and durations — the old YogaScreen sequence
///    (1 set, 3 s transitions between poses).
///  * Pranayama practices and durations — the old PranayamaScreen
///    sequence (1 set, 5 s transitions).
///  * Meditation presets 5/10/20/30/45 min — the milestone spec.
///
/// One generic session screen runs any [PracticeDefinition].
library;

/// The family a practice belongs to (drives tab placement/labels).
enum PracticeKind { strength, yoga, pranayama, meditation }

/// Bundled image shown while meditating.
const String meditationImageAsset = 'assets/images/meditation_image.jpg';

/// Bundled image shown during every interval practice's rest phase.
const String restPhaseImageAsset = 'assets/images/rest.jpg';

/// Bundled practice-length audio tracks (paths are relative to the
/// Flutter `assets/` directory, as audioplayers' AssetSource expects).
const String workoutAudioTrack = 'sounds/workout.mp3';
const String yogaAudioTrack = 'sounds/yoga.mp3';

/// One selectable guided-meditation soundtrack. A null [audioTrack]
/// means the meditation is intentionally silent.
class GuidedTrackOption {
  final String label;
  final String? audioTrack;

  const GuidedTrackOption(this.label, this.audioTrack);
}

/// Guided tracks offered beside the meditation duration presets,
/// in display order.
const List<GuidedTrackOption> guidedTrackOptions = [
  GuidedTrackOption('Breath', 'sounds/breath.mp3'),
  GuidedTrackOption('Body scan', 'sounds/bodyscan.m4a'),
  GuidedTrackOption('Relax', 'sounds/relax.mp3'),
  GuidedTrackOption('Silent', null),
];

/// The guided track selected until the user chooses another one.
const GuidedTrackOption defaultGuidedTrack = GuidedTrackOption(
  'Breath',
  'sounds/breath.mp3',
);

/// One timed step inside a practice (an exercise, a pose, or a
/// breathing practice).
class PracticeStep {
  final String name;
  final int seconds;

  /// Bundled image to show during this step, when one exists.
  final String? imageAsset;

  const PracticeStep(this.name, this.seconds, {this.imageAsset});
}

/// A complete, runnable practice definition.
class PracticeDefinition {
  final String id;
  final String title;
  final PracticeKind kind;
  final List<PracticeStep> steps;

  /// How many times the whole step list repeats.
  final int sets;

  /// Rest seconds between steps (0 = flow straight on).
  final int restSeconds;

  /// Counter noun: 'Exercise', 'Pose', 'Practice', 'Step'.
  final String unitLabel;

  final String description;

  /// Bundled image associated with the whole practice, when a
  /// step-specific image is not the right representation.
  final String? imageAsset;

  /// Bundled practice-length soundtrack, relative to `assets/`.
  /// Null means the practice runs silently.
  final String? audioTrack;

  const PracticeDefinition({
    required this.id,
    required this.title,
    required this.kind,
    required this.steps,
    required this.sets,
    required this.restSeconds,
    required this.unitLabel,
    required this.description,
    this.imageAsset,
    this.audioTrack,
  });

  /// Total planned work seconds (rests excluded).
  int get workSeconds =>
      steps.fold<int>(0, (sum, step) => sum + step.seconds) * sets;

  /// True when the session has more than one step or set — those are
  /// the practices where Skip and the counters apply.
  bool get isInterval => steps.length > 1 || sets > 1;
}

/// The spec'd upper-body routine: exactly these five, 45/15 × 3.
const PracticeDefinition strengthUpper = PracticeDefinition(
  id: 'strength-upper',
  title: 'Upper Body',
  kind: PracticeKind.strength,
  steps: [
    PracticeStep('Pushups', 45),
    PracticeStep('Plank Ups', 45),
    PracticeStep('Plank to Dolphin', 45),
    PracticeStep('Superman', 45),
    PracticeStep('Plank', 45),
  ],
  sets: 3,
  restSeconds: 15,
  unitLabel: 'Exercise',
  description: 'Push, plank and pull strength for the upper body.',
  audioTrack: workoutAudioTrack,
);

/// Lower-body routine from the old app's content: six moves, 45/15 × 3.
const PracticeDefinition strengthLower = PracticeDefinition(
  id: 'strength-lower',
  title: 'Lower Body',
  kind: PracticeKind.strength,
  steps: [
    PracticeStep('Squats', 45, imageAsset: 'assets/images/lower/squat.gif'),
    PracticeStep(
      'Right Lunge',
      45,
      imageAsset: 'assets/images/lower/lunge.gif',
    ),
    PracticeStep('Left Lunge', 45, imageAsset: 'assets/images/lower/lunge.gif'),
    PracticeStep(
      'Side Lunges Right',
      45,
      imageAsset: 'assets/images/lower/side_lunge.gif',
    ),
    PracticeStep(
      'Side Lunges Left',
      45,
      imageAsset: 'assets/images/lower/side_lunge.gif',
    ),
    PracticeStep(
      'Glute Bridge',
      45,
      imageAsset: 'assets/images/lower/glute_bridge.gif',
    ),
  ],
  sets: 3,
  restSeconds: 15,
  unitLabel: 'Exercise',
  description: 'Squat, lunge and bridge strength for the lower body.',
  audioTrack: workoutAudioTrack,
);

/// One-based day of the year for [date]: January 1 is day 1.
///
/// Computed in UTC so daylight-saving shifts cannot skew the count.
int dayOfYear(DateTime date) {
  final startOfYear = DateTime.utc(date.year, 1, 1);
  final day = DateTime.utc(date.year, date.month, date.day);
  return day.difference(startOfYear).inDays + 1;
}

/// Morning strength alternation: upper body on odd days of the year,
/// lower body on even days.
bool isUpperBodyDay(DateTime date) => dayOfYear(date).isOdd;

/// The strength routine scheduled for [date].
PracticeDefinition strengthForDate(DateTime date) =>
    isUpperBodyDay(date) ? strengthUpper : strengthLower;

/// The old app's yoga sequence: ten poses, one set, brief transitions.
const PracticeDefinition yogaPractice = PracticeDefinition(
  id: 'yoga',
  title: 'Yoga',
  kind: PracticeKind.yoga,
  steps: [
    PracticeStep(
      'Downward Dog',
      40,
      imageAsset: 'assets/images/yoga/downward-facingdog.png',
    ),
    PracticeStep('Plank', 20, imageAsset: 'assets/images/yoga/plankpose.png'),
    PracticeStep(
      'Seated Forward Bend',
      90,
      imageAsset: 'assets/images/yoga/seatedforward.jpg',
    ),
    PracticeStep(
      'Cobblers Pose',
      60,
      imageAsset: 'assets/images/yoga/boundangle.jpg',
    ),
    PracticeStep(
      'Seated Twist Right',
      60,
      imageAsset: 'assets/images/yoga/twist.jpg',
    ),
    PracticeStep(
      'Seated Twist Left',
      60,
      imageAsset: 'assets/images/yoga/twist.jpg',
    ),
    PracticeStep(
      'Bridge Pose',
      90,
      imageAsset: 'assets/images/yoga/bridgepose.png',
    ),
    // No Cobra image exists in the bundled media; the session UI
    // deliberately handles this step's null image gracefully.
    PracticeStep('Cobra', 90),
    PracticeStep(
      'Shoulder stand',
      180,
      imageAsset: 'assets/images/yoga/shoulderstand.png',
    ),
    PracticeStep(
      'Shavasana (corpse)',
      180,
      imageAsset: 'assets/images/yoga/corpse-pose.jpg',
    ),
  ],
  sets: 1,
  restSeconds: 3,
  unitLabel: 'Pose',
  description:
      'Yoga is great for flexibility and mobility — feel calmer and well rested.',
  audioTrack: yogaAudioTrack,
);

/// The old app's pranayama sequence: five timed breathing practices.
const PracticeDefinition pranayamaPractice = PracticeDefinition(
  id: 'pranayama',
  title: 'Pranayama',
  kind: PracticeKind.pranayama,
  steps: [
    PracticeStep('Bhastrika', 180),
    PracticeStep('Kapalbhati', 300),
    PracticeStep('Nadi Shodhan', 420),
    PracticeStep('Bhramari', 120),
    PracticeStep('Ujjayi', 180),
  ],
  sets: 1,
  restSeconds: 5,
  unitLabel: 'Practice',
  description: 'Five classical breathing practices, timed and guided.',
);

/// Meditation preset lengths, in minutes.
const List<int> meditationPresetMinutes = [5, 10, 20, 30, 45];

/// Builds the single-step meditation practice for a preset length.
///
/// Breath is the default guided soundtrack. Pass another track from
/// [guidedTrackOptions], including null for a silent meditation.
PracticeDefinition meditationPractice(
  int minutes, {
  String? audioTrack = 'sounds/breath.mp3',
}) => PracticeDefinition(
  id: 'meditation-$minutes',
  title: 'Meditation $minutes min',
  kind: PracticeKind.meditation,
  steps: [PracticeStep('Meditation', minutes * 60)],
  sets: 1,
  restSeconds: 0,
  unitLabel: 'Step',
  description: 'Sit comfortably and rest attention on the breath.',
  imageAsset: meditationImageAsset,
  audioTrack: audioTrack,
);

/// Every fixed (non-alternating, non-preset) practice, by id.
final Map<String, PracticeDefinition> _fixedPractices = {
  for (final practice in [
    strengthUpper,
    strengthLower,
    yogaPractice,
    pranayamaPractice,
  ])
    practice.id: practice,
};

/// Looks up any practice by id, including meditation presets
/// ('meditation-20'). Returns null for unknown ids.
PracticeDefinition? practiceById(String id) {
  final fixed = _fixedPractices[id];
  if (fixed != null) return fixed;
  if (id.startsWith('meditation-')) {
    final minutes = int.tryParse(id.substring('meditation-'.length));
    if (minutes != null && meditationPresetMinutes.contains(minutes)) {
      return meditationPractice(minutes);
    }
  }
  return null;
}
