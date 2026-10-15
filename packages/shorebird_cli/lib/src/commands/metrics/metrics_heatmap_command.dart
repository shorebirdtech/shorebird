import 'package:shorebird_cli/src/commands/metrics/metrics_subcommand.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

const _jsonExample = 'shorebird metrics heatmap --app-id <id> --json';

/// Day names indexed by the API's `day_of_week_utc` minus one
/// (1 = Sunday, 7 = Saturday).
const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// {@template metrics_heatmap_command}
/// `shorebird metrics heatmap`
/// Show average active devices for each day of the week and hour of the day.
/// {@endtemplate}
class MetricsHeatmapCommand
    extends MetricsSubcommand<GetActivityHeatmapResponse> {
  @override
  String get name => 'heatmap';

  @override
  String get metricName => 'activity heatmap';

  @override
  String get description =>
      'Show the average number of active devices for each day of the week '
      'and hour of the day (UTC).\n\n'
      'Example output (one row per day, one column per hour, rounded):\n'
      '  Average active devices by day and hour (UTC) over the last 28 '
      'days:\n'
      '         00   01   02  ...\n'
      '    Sun  410  388  350 ...\n'
      '  Busiest: Mon 14:00 UTC\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<GetActivityHeatmapResponse> request(
    CodePushClient client, {
    required String appId,
    int? releaseId,
  }) => client.getActivityHeatmap(appId: appId);

  @override
  Map<String, dynamic> toJson(GetActivityHeatmapResponse response) =>
      response.toJson();

  @override
  void printResult(GetActivityHeatmapResponse response) {
    logger.info(
      'Average active devices by day and hour (UTC) over the last '
      '${response.lookbackDays} days:',
    );

    final grid = List.generate(7, (_) => List<String>.filled(24, '0'));
    for (final cell in response.cells) {
      final day = cell.dayOfWeekUtc - 1;
      if (day < 0 || day >= 7 || cell.hourUtc < 0 || cell.hourUtc >= 24) {
        continue;
      }
      grid[day][cell.hourUtc] = cell.averageActiveDevices.round().toString();
    }
    final width = [
      2,
      for (final row in grid) ...row.map((v) => v.length),
    ].reduce((a, b) => a > b ? a : b);
    String pad(String value) => value.padLeft(width);

    final hours = [
      for (var hour = 0; hour < 24; hour++)
        pad(hour.toString().padLeft(2, '0')),
    ];
    logger.info('       ${hours.join(' ')}');
    for (var day = 0; day < 7; day++) {
      logger.info('  ${_dayNames[day]}  ${grid[day].map(pad).join(' ')}');
    }

    final busiestDay = response.busiestDayOfWeekUtc;
    final busiestHour = response.busiestHourUtc;
    if (busiestDay == null || busiestHour == null) {
      logger.info('Not enough data yet to find the busiest hour.');
      return;
    }
    logger.info(
      'Busiest: ${_dayNames[busiestDay - 1]} ${formatHour(busiestHour)} UTC',
    );
  }
}
