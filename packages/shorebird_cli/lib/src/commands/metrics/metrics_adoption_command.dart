import 'package:shorebird_cli/src/commands/metrics/metrics_subcommand.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

const _jsonExample =
    'shorebird metrics adoption --release-version 1.0.0+1 --app-id <id> '
    '--json';

/// {@template metrics_adoption_command}
/// `shorebird metrics adoption`
/// Show the share of a release's devices running each of its patches.
/// {@endtemplate}
class MetricsAdoptionCommand
    extends MetricsSubcommand<GetPatchAdoptionResponse> {
  /// {@macro metrics_adoption_command}
  MetricsAdoptionCommand() {
    argParser.addOption(
      CommonArguments.releaseVersionArg.name,
      help:
          'The release to report on (e.g. "1.0.0+1"). '
          "Defaults to the app's latest release.",
    );
    addWindowOptions();
    addGranularityOption(
      help:
          'Bucket size for a time series. Omit for a single value per patch '
          'over the whole window.',
    );
  }

  @override
  String get name => 'adoption';

  @override
  String get metricName => 'patch adoption';

  @override
  String get description =>
      "Show the share of a release's devices running each of its patches "
      '(that patch or a later one).\n\n'
      'Example output (one line per patch):\n'
      '  Patch adoption for release 1.0.0+1 (latest release)\n'
      '    Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z\n'
      '    #1  android, ios  92.4%  (2310 of 2500 devices)\n'
      '    #2  android, ios  61.0%  (1525 of 2500 devices)\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<GetPatchAdoptionResponse> request(
    CodePushClient client, {
    required String appId,
    int? releaseId,
  }) => client.getPatchAdoption(
    appId: appId,
    releaseVersion: releaseVersion,
    start: start,
    end: end,
    granularity: results['granularity'] as String?,
  );

  @override
  Map<String, dynamic> toJson(GetPatchAdoptionResponse response) =>
      response.toJson();

  @override
  void printResult(GetPatchAdoptionResponse response) {
    final latest = response.isLatest ? ' (latest release)' : '';
    logger
      ..info('Patch adoption for release ${response.releaseVersion}$latest')
      ..info('  Window: ${formatMetricsRange(response.range)}');

    if (response.patches.isEmpty) {
      logger.info('  No patches found.');
      return;
    }

    String devices(PatchAdoptionPoint point) =>
        '(${point.devices} of ${point.target} devices)';

    for (final patch in response.patches) {
      final platforms = patch.targetPlatforms.map((p) => p.value).join(', ');
      final rolledBack = patch.isRolledBack ? '  [rolled back]' : '';
      final series = patch.series;
      if (series.length == 1 && series.single.period == null) {
        final point = series.single;
        logger.info(
          '  #${patch.patchNumber}  $platforms  '
          '${formatPercent(point.adoptionPct)}  ${devices(point)}$rolledBack',
        );
        continue;
      }
      logger.info('  #${patch.patchNumber}  $platforms$rolledBack');
      logTable(indent: '    ', [
        for (final point in series)
          [
            if (point.period case final period?)
              formatMetricsTime(period)
            else
              'whole window',
            formatPercent(point.adoptionPct),
            devices(point),
          ],
      ]);
    }
  }
}
