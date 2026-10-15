import 'package:shorebird_cli/src/commands/metrics/metrics_subcommand.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

const _jsonExample = 'shorebird metrics versions --app-id <id> --json';

/// {@template metrics_versions_command}
/// `shorebird metrics versions`
/// Show how active devices are distributed across release versions.
/// {@endtemplate}
class MetricsVersionsCommand
    extends MetricsSubcommand<GetVersionDistributionResponse> {
  @override
  String get name => 'versions';

  @override
  String get metricName => 'version distribution';

  @override
  String get description =>
      'Show how recently active devices are distributed across release '
      'versions.\n\n'
      'Example output (one line per release version):\n'
      '  Active devices in the last 28 days: 8400\n'
      '    1.0.1+2  6300  75.0%\n'
      '    1.0.0+1  2100  25.0%\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<GetVersionDistributionResponse> request(
    CodePushClient client, {
    required String appId,
    int? releaseId,
  }) => client.getVersionDistribution(appId: appId);

  @override
  Map<String, dynamic> toJson(GetVersionDistributionResponse response) =>
      response.toJson();

  @override
  void printResult(GetVersionDistributionResponse response) {
    logger.info(
      'Active devices in the last ${response.activeWindowDays} days: '
      '${response.totalDevices}',
    );
    logTable([
      for (final entry in response.entries)
        [
          entry.releaseVersion ?? '(unknown)',
          '${entry.deviceCount}',
          formatPercent(entry.percentage),
        ],
    ]);
  }
}
