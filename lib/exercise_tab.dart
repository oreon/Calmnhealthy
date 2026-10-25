import 'package:flutter/material.dart';

import 'practice_catalog.dart';
import 'practice_start.dart';
import 'session_engine.dart';
import 'session_store.dart';

/// The Exercise tab: today's strength routine (upper/lower by
/// day-of-year alternation) plus the yoga and pranayama practices.
class ExerciseTab extends StatefulWidget {
  const ExerciseTab({super.key});

  @override
  State<ExerciseTab> createState() => _ExerciseTabState();
}

class _ExerciseTabState extends State<ExerciseTab> {
  SessionDraft? _draft;

  @override
  void initState() {
    super.initState();
    _loadDraft();
    SessionStore.changes.addListener(_loadDraft);
  }

  @override
  void dispose() {
    SessionStore.changes.removeListener(_loadDraft);
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final draft = await SessionStore.loadDraft(cnhDateKey(DateTime.now()));
    if (!mounted) return;
    setState(() => _draft = draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strength = strengthForDate(DateTime.now());
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Exercise',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _practiceCard(
            theme,
            practice: strength,
            heading: 'Strength — ${strength.title} today',
            meta:
                '${strength.steps.length} exercises · '
                '${strength.steps.first.seconds}s work · '
                '${strength.restSeconds}s rest · ${strength.sets} sets',
            showStepThumbnails: true,
          ),
          const SizedBox(height: 12),
          _practiceCard(
            theme,
            practice: yogaPractice,
            heading: 'Yoga',
            meta:
                '${yogaPractice.steps.length} poses · '
                'about ${yogaPractice.workSeconds ~/ 60} min',
          ),
          const SizedBox(height: 12),
          _practiceCard(
            theme,
            practice: pranayamaPractice,
            heading: 'Pranayama',
            meta:
                '${pranayamaPractice.steps.length} practices · '
                'about ${pranayamaPractice.workSeconds ~/ 60} min',
          ),
        ],
      ),
    );
  }

  Widget _practiceCard(
    ThemeData theme, {
    required PracticeDefinition practice,
    required String heading,
    required String meta,
    bool showStepThumbnails = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              meta,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (showStepThumbnails)
              _strengthStepList(theme, practice)
            else
              Text(
                practice.steps.map((step) => step.name).join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),
            PracticeStartActions(
              practice: practice,
              draft: _draft,
              onChanged: _loadDraft,
            ),
          ],
        ),
      ),
    );
  }

  Widget _strengthStepList(ThemeData theme, PracticeDefinition practice) {
    return Column(
      children: [
        for (var i = 0; i < practice.steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: practice.steps[i].imageAsset == null
                    ? Icon(
                        Icons.fitness_center,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          practice.steps[i].imageAsset!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  practice.steps[i].name,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '${practice.steps[i].seconds}s',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
