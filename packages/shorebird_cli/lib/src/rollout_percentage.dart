/// Percentage rollouts: offering a patch to a share of the devices on its
/// track.
library;

/// The name of the `--rollout` option on `shorebird patch` and
/// `shorebird patches set-track`/`promote`.
const rolloutArgName = 'rollout';

/// Help for `--rollout`, on a command that puts [subject] on a track.
String rolloutHelp(String subject) =>
    "The percentage of the track's devices to offer $subject to, a number "
    'greater than 0 and at most 100 with at most two decimal places '
    '(e.g. "10"). Defaults to 100. Raise it later with '
    '`shorebird patches rollout`.';

/// The command that raises the rollout of patch [patchNumber] on release
/// [releaseVersion] to [percentage], or to a placeholder when that is null.
/// [appId] and [flavor] are passed through when given.
String raiseRolloutCommand({
  required String releaseVersion,
  required int patchNumber,
  double? percentage,
  String? appId,
  String? flavor,
}) => [
  'shorebird patches rollout',
  '--release-version $releaseVersion',
  '--patch-number $patchNumber',
  if (appId != null) '--app-id $appId',
  if (flavor != null) '--flavor $flavor',
  if (percentage == null)
    '--percentage <percentage>'
  else
    '--percentage ${formatRolloutArgument(percentage)}',
].join(' ');

/// Said wherever a rollout below 100% is set. Engines before Flutter 3.35.7
/// send no per-install id to bucket on, so the server treats those devices as
/// outside every rollout.
const rolloutOlderDevicesNote =
    'Rollout percentages count devices on Flutter 3.35.7 and later; older '
    'devices get this patch only once it reaches 100%.';

/// A percentage written as a number with at most two decimal places, with an
/// optional trailing `%`.
final _percentagePattern = RegExp(r'^(\d+(\.\d{1,2})?|\.\d{1,2})%?$');

/// Parses [value], the argument to `--[argName]`, as a rollout percentage: a
/// number greater than 0 and at most 100 with at most two decimal places.
///
/// Returns the percentage, or an error naming the flag and the value given.
({double? percentage, String? error}) parseRolloutPercentage(
  String value, {
  required String argName,
}) {
  final trimmed = value.trim();
  final percentage = _percentagePattern.hasMatch(trimmed)
      ? double.parse(trimmed.replaceFirst('%', ''))
      : null;
  if (percentage == null || percentage <= 0 || percentage > 100) {
    return (
      percentage: null,
      error:
          '--$argName must be a percentage greater than 0 and at most 100, '
          'with at most two decimal places, such as 10 or 0.5 '
          '(got "$value").',
    );
  }
  return (percentage: percentage, error: null);
}

/// Formats [percentage] without a trailing `.0`, e.g. `10%` or `12.5%`.
String formatRolloutPercentage(double percentage) =>
    '${formatRolloutArgument(percentage)}%';

/// Formats [percentage] as it is written on the command line, e.g. `10` or
/// `12.5`.
String formatRolloutArgument(double percentage) =>
    percentage == percentage.truncateToDouble()
    ? percentage.toInt().toString()
    : percentage.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
