import 'package:material_ui/material_ui.dart';

import '../../core/local_date.dart';
import '../../domain/occurrence.dart';
import '../formatting.dart';

/// Upcoming times grouped by day, each shown once (with its end, if any):
/// `Tomorrow        [09:00 – 12:00] [15:00]`.
class OccurrenceTimes extends StatelessWidget {
  const OccurrenceTimes({
    required this.occurrences,
    required this.now,
    super.key,
  });

  final List<Occurrence> occurrences;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final formatter = TimeFormatter.of(context);
    final today = LocalDate.fromDateTime(now);

    final groups = <(LocalDate, List<Occurrence>)>[];
    for (final occurrence in occurrences) {
      final day = occurrence.date;
      if (groups.isEmpty || groups.last.$1 != day) {
        groups.add((day, [occurrence]));
      } else {
        groups.last.$2.add(occurrence);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (day, dayOccurrences) in groups)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      formatDay(day, today),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final occurrence in dayOccurrences)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            formatOccurrenceSpan(
                              occurrence.start,
                              occurrence.end,
                              formatter,
                            ),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onTertiaryContainer,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
