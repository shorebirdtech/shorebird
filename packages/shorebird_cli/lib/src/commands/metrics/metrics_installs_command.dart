import 'package:shorebird_cli/src/commands/metrics/metrics_patch_count_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

const _jsonExample = 'shorebird metrics installs --app-id <id> --json';

/// {@template metrics_installs_command}
/// `shorebird metrics installs`
/// Show how many times patches were installed.
/// {@endtemplate}
class MetricsInstallsCommand extends MetricsPatchCountCommand {
  @override
  String get name => 'installs';

  @override
  String get metricName => 'patch installs';

  @override
  String get title => 'Patch installs';

  @override
  String get description =>
      'Show how many times patches were installed on devices, for the app or '
      'one release, compared with the previous window of the same length.\n\n'
      'Example output:\n'
      '  Patch installs: 1520\n'
      '    Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z\n'
      '    Previous window: 1210 '
      '(2026-08-20T00:00:00Z to 2026-09-17T00:00:00Z)\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<GetPatchMetricResponse> request(
    CodePushClient client, {
    required String appId,
    int? releaseId,
  }) {
    if (releaseId != null) {
      return client.getReleasePatchInstalls(
        appId: appId,
        releaseId: releaseId,
        start: start,
        end: end,
        granularity: results['granularity'] as String?,
        groupBy: groupBy,
      );
    }
    return client.getAppPatchInstalls(
      appId: appId,
      start: start,
      end: end,
      granularity: results['granularity'] as String?,
      groupBy: groupBy,
    );
  }
}
