import 'package:material_ui/material_ui.dart';

import '../../core/local_date.dart';
import '../formatting.dart';

/// Activation times grouped by day:
/// `Tomorrow        [9:00 AM] [10:00 AM]`.
class ActivationTimes extends StatelessWidget {
  const ActivationTimes({required this.times, required this.now, super.key});

  final List<DateTime> times;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final formatter = TimeFormatter.of(context);
    final today = LocalDate.fromDateTime(now);

    final groups = <(LocalDate, List<DateTime>)>[];
    for (final at in times) {
      final day = LocalDate.fromDateTime(at);
      if (groups.isEmpty || groups.last.$1 != day) {
        groups.add((day, [at]));
      } else {
        groups.last.$2.add(at);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (day, dayTimes) in groups)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
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
                      for (final at in dayTimes)
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
                            formatter.instant(at),
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
