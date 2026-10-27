import 'package:shorebird_cli/src/commands/metrics/metrics_subcommand.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

const _jsonExample = 'shorebird metrics users --app-id <id> --json';

/// {@template metrics_users_command}
/// `shorebird metrics users`
/// Show the number of unique devices running the app.
/// {@endtemplate}
class MetricsUsersCommand extends MetricsSubcommand<GetUniqueUsersResponse> {
  /// {@macro metrics_users_command}
  MetricsUsersCommand() {
    addWindowOptions();
    addGranularityOption(
      help:
          'Bucket size for a time series. Omit for a single total per '
          'window.',
    );
    argParser.addOption(
      'group-by',
      allowed: GetUniqueUsersGroupBy.values.map((g) => g.value),
      help:
          'Break the total down by a dimension. With release_version, '
          'devices too old to report one are grouped as "(unknown)".',
    );
  }

  @override
  String get name => 'users';

  @override
  String get metricName => 'unique users';

  @override
  String get description =>
      'Show the number of unique devices running the app, compared with the '
      'previous window of the same length.\n\n'
      'Example output:\n'
      '  Unique users: 8400\n'
      '    Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z\n'
      '    Previous window: 7900 '
      '(2026-08-20T00:00:00Z to 2026-09-17T00:00:00Z)\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<GetUniqueUsersResponse> request(
    CodePushClient client, {
    required String appId,
    int? releaseId,
  }) => client.getUniqueUsers(
    appId: appId,
    start: start,
    end: end,
    granularity: results['granularity'] as String?,
    groupBy: results['group-by'] as String?,
  );

  @override
  Map<String, dynamic> toJson(GetUniqueUsersResponse response) =>
      response.toJson();

  @override
  void printResult(GetUniqueUsersResponse response) {
    final current = response.current;
    logger
      ..info('Unique users: ${current.uniqueUsers}')
      ..info('  Window: ${formatMetricsRange(current.range)}');
    final previous = response.previous;
    if (previous != null) {
      logger.info(
        '  Previous window: ${previous.uniqueUsers} '
        '(${formatMetricsRange(previous.range)})',
      );
    }

    final timeSeries = current.timeSeries;
    if (timeSeries != null && timeSeries.isNotEmpty) {
      logger.info('Time series (${response.granularity}):');
      logTable([
        for (final entry in timeSeries)
          [formatMetricsTime(entry.period), '${entry.uniqueUsers}'],
      ]);
    }

    final breakdown = current.breakdown;
    if (breakdown != null && breakdown.isNotEmpty) {
      logger.info('By ${breakdown.first.groupBy}:');
      logTable([
        for (final entry in breakdown)
          [
            if (entry.groupValue.isEmpty) '(unknown)' else entry.groupValue,
            '${entry.uniqueUsers}',
          ],
      ]);
    }
  }
}
