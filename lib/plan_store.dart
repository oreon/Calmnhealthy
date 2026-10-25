/// SharedPreferences persistence for the user's configured day
/// plan (Configure Your Day). The template lives under its own key
/// so resetting it can never touch points, history or drafts.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'today_plan.dart';

class PlanStore {
  /// The user's plan template as JSON. Absent (or unreadable) means
  /// the seeded default plan.
  static const String templateKey = 'cnh.plan_template';

  /// The user's plan: their saved template when present, else a
  /// copy of the seeded 13-task default.
  static Future<List<PlanTask>> loadPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(templateKey);
    if (raw == null) return List<PlanTask>.of(seedTasks);
    return decodePlanTemplate(raw) ?? List<PlanTask>.of(seedTasks);
  }

  /// Persists the plan as the user's template.
  static Future<void> savePlan(List<PlanTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(templateKey, encodePlanTemplate(tasks));
  }

  /// Removes ONLY the template key — lifetime points, per-day
  /// completion, session drafts and logs are all left untouched.
  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(templateKey);
  }
}
