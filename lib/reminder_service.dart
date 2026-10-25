/// Daily task reminders: one phone notification at each task's
/// scheduled time, following the user's configured day.
///
/// Like [AudioService], this is failure-isolated and lazily
/// initialized: the notifications plugin is only touched the first
/// time a reminder sync actually runs (post-first-frame, after
/// onboarding, after a plan edit, or from the Today bell toggle) —
/// never on app startup's critical path. Every plugin/timezone
/// failure is swallowed: reminders silently stay off and the app
/// remains fully functional.
library;

import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'plan_store.dart';
import 'today_plan.dart';

/// SharedPreferences key for the reminders on/off flag.
const String remindersEnabledKey = 'cnh.reminders_enabled';

/// SharedPreferences key for the persisted task-id → notification-id
/// map (JSON object), so a task keeps the same notification id
/// across edits, renames and reschedules.
const String reminderIdsKey = 'cnh.reminder_ids';

/// Whether the one-time Android permission request has been made.
const String _permissionAskedKey = 'cnh.reminders_permission_asked';

const String reminderChannelId = 'cnh_task_reminders';
const String reminderChannelName = 'Task reminders';
const String reminderChannelDescription =
    'A gentle nudge when a task in your day is due.';

/// Title on every task reminder; the body is the task's name.
const String reminderTitle = 'Calm n Healthy';

/// One daily reminder to schedule: [notificationId] at
/// [hour]:[minute] local time, repeating every day.
class ReminderSpec {
  final int notificationId;
  final String taskId;
  final String body;
  final int hour;
  final int minute;

  const ReminderSpec({
    required this.notificationId,
    required this.taskId,
    required this.body,
    required this.hour,
    required this.minute,
  });

  @override
  bool operator ==(Object other) =>
      other is ReminderSpec &&
      other.notificationId == notificationId &&
      other.taskId == taskId &&
      other.body == body &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(notificationId, taskId, body, hour, minute);
}

/// Returns [existing] plus an id allocation for any plan task that
/// does not have one yet. Existing entries are NEVER changed or
/// removed — not even for tasks that left the plan — so a task's
/// notification id is stable for the life of the install, and an id
/// is never reused by a different task. New ids continue above the
/// highest allocated id, starting at 1.
Map<String, int> assignReminderIds(
  List<PlanTask> plan,
  Map<String, int> existing,
) {
  final result = Map<String, int>.of(existing);
  var next = 1;
  for (final id in result.values) {
    if (id >= next) next = id + 1;
  }
  for (final task in plan) {
    if (!result.containsKey(task.id)) {
      result[task.id] = next;
      next += 1;
    }
  }
  return result;
}

/// The reminders to schedule for [plan]: one spec per task, using
/// the ids from [idMap] (allocating on the fly for any task the map
/// does not cover yet). Ordered by time of day, then task id, so the
/// result is deterministic for a given plan.
List<ReminderSpec> buildReminderSpecs(
  List<PlanTask> plan,
  Map<String, int> idMap,
) {
  final assigned = assignReminderIds(plan, idMap);
  final ordered = List<PlanTask>.of(plan)..sort((a, b) {
    final byTime = a.minutesOfDay.compareTo(b.minutesOfDay);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return [
    for (final task in ordered)
      ReminderSpec(
        notificationId: assigned[task.id]!,
        taskId: task.id,
        body: task.name,
        hour: task.hour,
        minute: task.minute,
      ),
  ];
}

/// Serializes the task-id → notification-id map for storage.
String encodeReminderIds(Map<String, int> map) => jsonEncode(map);

/// Parses the stored id map. Anything unreadable — missing, corrupt,
/// wrong shapes — decodes to an empty (or partial-but-valid) map
/// rather than throwing.
Map<String, int> decodeReminderIds(String? raw) {
  if (raw == null) return <String, int>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, int>{};
    final result = <String, int>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is int) result[key] = value;
    }
    return result;
  } catch (_) {
    return <String, int>{};
  }
}

/// The small platform surface [ReminderService] needs. Tests inject
/// a fake implementation, so unit tests never touch platform
/// channels.
abstract interface class ReminderBackend {
  /// Prepares the plugin and the local timezone. Called lazily,
  /// never during app startup.
  Future<void> initialize();

  /// Asks Android for the notification permission. Returns the
  /// grant result when the platform reports one.
  Future<bool> requestPermission();

  /// Schedules (or replaces) one daily reminder.
  Future<void> scheduleDaily(ReminderSpec spec);

  /// Cancels one scheduled reminder by notification id.
  Future<void> cancel(int notificationId);
}

/// flutter_local_notifications-backed implementation. The timezone
/// is read from the device via flutter_timezone; any failure there
/// falls back to UTC rather than failing initialization.
class LocalNotificationsBackend implements ReminderBackend {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    var location = tz.getLocation('UTC');
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      location = tz.getLocation(info.identifier);
    } catch (_) {
      // Keep the UTC fallback: reminders fire at the right wall
      // clock only in the device zone, but a wrong-zone reminder
      // beats taking the feature (or the app) down.
    }
    tz.setLocalLocation(location);
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> scheduleDaily(ReminderSpec spec) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      spec.hour,
      spec.minute,
    );
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: spec.notificationId,
      title: reminderTitle,
      body: spec.body,
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          reminderChannelId,
          reminderChannelName,
          channelDescription: reminderChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel(int notificationId) async {
    await _plugin.cancel(id: notificationId);
  }
}

/// Facade the UI talks to. All operations are guarded end-to-end:
/// no method ever throws.
class ReminderService {
  final ReminderBackend _backend;
  bool _backendReady = false;

  ReminderService({ReminderBackend? backend})
    : _backend = backend ?? LocalNotificationsBackend();

  /// The app-wide service. Constructed (but NOT initialized) on
  /// first access; the plugin initializes on first actual use.
  static final ReminderService instance = ReminderService();

  Future<bool> _ensureReady() async {
    if (_backendReady) return true;
    try {
      await _backend.initialize();
      _backendReady = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether reminders are switched on. Defaults to true; a storage
  /// error also resolves to the default rather than failing.
  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(remindersEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Syncs scheduled reminders to the user's saved plan (template
  /// or seed). Fire-and-forget safe: callers may `unawaited(...)`.
  Future<void> syncReminders() async {
    try {
      if (!await isEnabled()) return;
      final plan = await PlanStore.loadPlan();
      await rescheduleAll(plan);
    } catch (_) {
      // Reminders are an enhancement; failure stays silent.
    }
  }

  /// Cancels every previously scheduled reminder and schedules one
  /// per task in [plan]. Does nothing while reminders are off.
  Future<void> rescheduleAll(List<PlanTask> plan) async {
    try {
      if (!await isEnabled()) return;
      if (!await _ensureReady()) return;
      final prefs = await SharedPreferences.getInstance();

      // The Android permission is requested once, the first time
      // reminders are actually scheduled. If it is denied we simply
      // stay silent — no dialogs, no nagging, on any later sync.
      if (!(prefs.getBool(_permissionAskedKey) ?? false)) {
        try {
          await _backend.requestPermission();
        } catch (_) {
          // A failed request counts as asked: never nag.
        }
        await prefs.setBool(_permissionAskedKey, true);
      }

      final stored = decodeReminderIds(prefs.getString(reminderIdsKey));
      final idMap = assignReminderIds(plan, stored);
      for (final id in stored.values.toSet()) {
        try {
          await _backend.cancel(id);
        } catch (_) {
          // One stuck cancellation must not block the reschedule.
        }
      }
      for (final spec in buildReminderSpecs(plan, idMap)) {
        try {
          await _backend.scheduleDaily(spec);
        } catch (_) {
          // One failed schedule must not block the rest.
        }
      }
      await prefs.setString(reminderIdsKey, encodeReminderIds(idMap));
    } catch (_) {
      // Reminders are an enhancement; failure stays silent.
    }
  }

  /// Cancels every reminder this app has scheduled (the persisted
  /// id map is kept, so re-enabling restores the same ids).
  Future<void> cancelAll() async {
    try {
      if (!await _ensureReady()) return;
      final prefs = await SharedPreferences.getInstance();
      final idMap = decodeReminderIds(prefs.getString(reminderIdsKey));
      for (final id in idMap.values.toSet()) {
        try {
          await _backend.cancel(id);
        } catch (_) {
          // Best effort per reminder.
        }
      }
    } catch (_) {
      // Reminders are an enhancement; failure stays silent.
    }
  }

  /// The Today bell toggle: persists the flag, then either syncs
  /// reminders to the saved plan (on) or cancels them all (off).
  Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(remindersEnabledKey, enabled);
    } catch (_) {
      return;
    }
    if (enabled) {
      await syncReminders();
    } else {
      await cancelAll();
    }
  }
}
