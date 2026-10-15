import 'package:shorebird_cli/src/commands/metrics/metrics_subcommand.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// The `--group-by` value that breaks app-wide counts down by release.
final _appGroupBy = GetAppPatchInstallsParameter3.release.value;

/// The `--group-by` value that breaks a release's counts down by patch.
final _releaseGroupBy = GetReleasePatchInstallsParameter3.patch.value;

/// {@template metrics_patch_count_command}
/// Base class for `shorebird metrics installs` and
/// `shorebird metrics downloads`, which report a patch event count for an app
/// or, with `--release-version`, for one release.
/// {@endtemplate}
abstract class MetricsPatchCountCommand
    extends MetricsSubcommand<GetPatchMetricResponse> {
  /// {@macro metrics_patch_count_command}
  MetricsPatchCountCommand() {
    argParser.addOption(
      CommonArguments.releaseVersionArg.name,
      help:
          'Only count patches of this release (e.g. "1.0.0+1"). '
          'Defaults to all releases of the app.',
    );
    addWindowOptions();
    addGranularityOption(
      help:
          'Bucket size for a time series. Omit for a single total per '
          'window.',
    );
    argParser.addOption(
      'group-by',
      allowed: [_appGroupBy, _releaseGroupBy],
      allowedHelp: {
        _appGroupBy: 'Break the count down by release.',
        _releaseGroupBy:
            'Break the count down by patch number (requires '
            '--${CommonArguments.releaseVersionArg.name}).',
      },
      help: 'Break the count down by a dimension.',
    );
  }

  /// The noun for the count, capitalized (e.g. "Patch installs").
  String get title;

  @override
  bool get resolvesReleaseId => true;

  /// The `--group-by` value, or null when not passed.
  String? get groupBy => results['group-by'] as String?;

  @override
  void validateArgs() {
    super.validateArgs();
    final releaseArg = CommonArguments.releaseVersionArg.name;
    if (groupBy == _releaseGroupBy && releaseVersion == null) {
      usageException('--group-by $_releaseGroupBy requires --$releaseArg.');
    }
    if (groupBy == _appGroupBy && releaseVersion != null) {
      usageException(
        '--group-by $_appGroupBy cannot be combined with --$releaseArg. '
        'Use --group-by $_releaseGroupBy to break a release down by patch.',
      );
    }
  }

  @override
  Map<String, dynamic> toJson(GetPatchMetricResponse response) =>
      response.toJson();

  @override
  void printResult(GetPatchMetricResponse response) {
    final current = response.current;
    final scope = releaseVersion != null ? ' for release $releaseVersion' : '';
    logger
      ..info('$title$scope: ${current.count}')
      ..info('  Window: ${formatMetricsRange(current.range)}');
    final previous = response.previous;
    if (previous != null) {
      logger.info(
        '  Previous window: ${previous.count} '
        '(${formatMetricsRange(previous.range)})',
      );
    }

    final timeSeries = current.timeSeries;
    if (timeSeries != null && timeSeries.isNotEmpty) {
      logger.info('Time series (${response.granularity}):');
      logTable([
        for (final entry in timeSeries)
          [formatMetricsTime(entry.period), '${entry.count}'],
      ]);
    }

    final breakdown = current.breakdown;
    if (breakdown != null && breakdown.isNotEmpty) {
      logger.info('By ${breakdown.first.groupBy}:');
      logTable([
        for (final entry in breakdown) [entry.groupValue, '${entry.count}'],
      ]);
    }
  }
}
