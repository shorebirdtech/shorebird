import 'package:shorebird_cli/src/commands/metrics/metrics_subcommand.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

const _jsonExample = 'shorebird metrics active-hours --app-id <id> --json';

/// {@template metrics_active_hours_command}
/// `shorebird metrics active-hours`
/// Show average active devices per hour of the day, and the quietest window
/// to release in.
/// {@endtemplate}
class MetricsActiveHoursCommand
    extends MetricsSubcommand<GetActiveHoursResponse> {
  @override
  String get name => 'active-hours';

  @override
  String get metricName => 'active hours';

  @override
  String get description =>
      'Show the average number of active devices for each hour of the day '
      '(UTC), with a recommended low-activity window to release in.\n\n'
      'Example output (one line per hour):\n'
      '  Average active devices by hour (UTC) over the last 28 days:\n'
      '    00:00  412.5\n'
      '    01:00  388.0\n'
      '    ...\n'
      '  Recommended release window: 03:00 to 05:00 UTC\n'
      '  Busiest hour: 14:00 UTC\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<GetActiveHoursResponse> request(
    CodePushClient client, {
    required String appId,
    int? releaseId,
  }) => client.getActiveHours(appId: appId);

  @override
  Map<String, dynamic> toJson(GetActiveHoursResponse response) =>
      response.toJson();

  @override
  void printResult(GetActiveHoursResponse response) {
    logger.info(
      'Average active devices by hour (UTC) over the last '
      '${response.lookbackDays} days:',
    );
    logTable([
      for (final entry in response.hourly)
        [
          formatHour(entry.hourUtc),
          entry.averageActiveDevices.toStringAsFixed(1),
        ],
    ]);

    final windowStart = response.recommendedWindowStartUtc;
    final busiest = response.busiestHourUtc;
    if (windowStart == null || busiest == null) {
      logger.info('Not enough data yet to recommend a release window.');
      return;
    }
    final windowEnd =
        (windowStart + response.recommendedWindowLengthHours) % 24;
    logger
      ..info(
        'Recommended release window: ${formatHour(windowStart)} to '
        '${formatHour(windowEnd)} UTC',
      )
      ..info('Busiest hour: ${formatHour(busiest)} UTC');
  }
}
