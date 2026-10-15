import 'package:shorebird_cli/src/commands/metrics/metrics_subcommand.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

const _jsonExample = 'shorebird metrics new-devices --app-id <id> --json';

/// {@template metrics_new_devices_command}
/// `shorebird metrics new-devices`
/// Show how many devices ran the app for the first time recently.
/// {@endtemplate}
class MetricsNewDevicesCommand
    extends MetricsSubcommand<GetNewDevicesResponse> {
  @override
  String get name => 'new-devices';

  @override
  String get metricName => 'new devices';

  @override
  String get description =>
      'Show how many devices ran the app for the first time recently, '
      'compared with the preceding window of the same length.\n\n'
      'Example output:\n'
      '  New devices in the last 28 days: 950\n'
      '    Previous 28 days: 870\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<GetNewDevicesResponse> request(
    CodePushClient client, {
    required String appId,
    int? releaseId,
  }) => client.getNewDevices(appId: appId);

  @override
  Map<String, dynamic> toJson(GetNewDevicesResponse response) =>
      response.toJson();

  @override
  void printResult(GetNewDevicesResponse response) {
    final days = response.windowDays;
    logger
      ..info('New devices in the last $days days: ${response.current}')
      ..info(
        '  Previous $days days: '
        '${response.previous ?? 'unavailable (before metrics were recorded)'}',
      );
  }
}
