/// Guarded, lazily-created audio playback for guided sessions.
///
/// This service is deliberately instantiated only by a session or a
/// completion screen — never during app startup. The platform player
/// itself is created even later, on the first actual play request.
/// Every backend failure is swallowed: audio is an enhancement to a
/// session, never a reason for the session to fail.
library;

import 'package:audioplayers/audioplayers.dart';

/// The small platform surface [AudioService] needs. Tests inject a
/// fake implementation, so unit tests never touch platform channels.
abstract interface class AudioBackend {
  Future<void> play(String track);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

/// audioplayers-backed implementation. Its [AudioPlayer] is created
/// lazily by the first play request; pause/resume/stop before any
/// playback therefore do not create a player at all.
///
/// [playerMode] stays on the media player for long session tracks.
/// Box-breathing phase cues pass [PlayerMode.lowLatency] so Android
/// plays the short chime through SoundPool instead of spinning up a
/// media player on every phase.
class AudioplayersBackend implements AudioBackend {
  AudioplayersBackend({this.playerMode = PlayerMode.mediaPlayer});

  final PlayerMode playerMode;
  AudioPlayer? _player;

  AudioPlayer get _ensurePlayer => _player ??= AudioPlayer();

  @override
  Future<void> play(String track) async {
    final player = _ensurePlayer;
    // Long tracks keep the default media player. Phase cues opt into
    // low latency, which audioplayers applies at play time.
    if (playerMode == PlayerMode.lowLatency) {
      await player.play(AssetSource(track), mode: PlayerMode.lowLatency);
    } else {
      await player.play(AssetSource(track));
    }
  }

  @override
  Future<void> pause() async {
    final player = _player;
    if (player != null) await player.pause();
  }

  @override
  Future<void> resume() async {
    final player = _player;
    if (player != null) await player.resume();
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player != null) await player.stop();
  }
}

/// A failure-isolating audio facade used by session UI.
class AudioService {
  /// Bundled bell played once when a completion screen appears.
  static const String completionBellTrack = 'sounds/tibet_bell.wav';

  /// Short chime played at each box-breathing phase change.
  /// Relative to `assets/`, like every other track.
  static const String phaseChimeTrack = 'sounds/phase_chime.wav';

  final AudioBackend _backend;
  bool _isPlaying = false;
  String? _currentTrack;

  AudioService({AudioBackend? backend})
    : _backend = backend ?? AudioplayersBackend();

  /// Cue player for box breathing. Low-latency on Android so a
  /// one-shot wav starts with the phase instead of waiting on the
  /// media player. Tests pass [backend] and never touch the platform.
  factory AudioService.phaseCues({AudioBackend? backend}) => AudioService(
    backend: backend ?? AudioplayersBackend(playerMode: PlayerMode.lowLatency),
  );

  /// Whether the most recent guarded playback operation left audio
  /// playing. Any backend error reports false.
  bool get isPlaying => _isPlaying;

  /// The track selected for playback, or null after stop/error and
  /// for a deliberately silent session.
  String? get currentTrack => _currentTrack;

  /// Starts [track], a path relative to `assets/`. Null/empty is a
  /// successful no-op representing silence.
  Future<void> play(String? track) async {
    if (track == null || track.isEmpty) {
      _currentTrack = null;
      _isPlaying = false;
      return;
    }
    try {
      await _backend.play(track);
      _currentTrack = track;
      _isPlaying = true;
    } catch (_) {
      _currentTrack = null;
      _isPlaying = false;
    }
  }

  /// Plays the completion bell once, with the same failure guard.
  Future<void> playCompletionBell() => play(completionBellTrack);

  /// Restarts the phase chime from the beginning. Stopping first
  /// matters when the previous cue is still ringing.
  Future<void> playPhaseChime() async {
    await stop();
    await play(phaseChimeTrack);
  }

  Future<void> pause() async {
    try {
      await _backend.pause();
    } catch (_) {
      // Playback state is uncertain after a platform error; report
      // not-playing rather than allowing the error to escape.
    }
    _isPlaying = false;
  }

  Future<void> resume() async {
    if (_currentTrack == null) return;
    try {
      await _backend.resume();
      _isPlaying = true;
    } catch (_) {
      _isPlaying = false;
    }
  }

  Future<void> stop() async {
    try {
      await _backend.stop();
    } catch (_) {
      // Stopping is best-effort and must never break navigation.
    }
    _currentTrack = null;
    _isPlaying = false;
  }
}
