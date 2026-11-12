/// Timed rollout schedules: a series of percentages the server raises a
/// patch's rollout through on its own.
library;

import 'package:args/args.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/rollout_percentage.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The name of the `--rollout-steps` option, which puts a patch on a timed
/// rollout schedule instead of a fixed percentage.
const rolloutStepsArgName = 'rollout-steps';

/// The name of the `--pause-weekends` flag, which holds a schedule's step
/// over Saturday and Sunday.
const pauseWeekendsArgName = 'pause-weekends';

/// The name of the `--timezone` option, whose clock and weekends a schedule
/// follows.
const timezoneArgName = 'timezone';

/// The fewest steps a schedule can have. One percentage is a fixed rollout,
/// not a schedule.
const minRolloutSteps = 2;

/// The most steps the server accepts in a schedule.
const maxRolloutSteps = 10;

/// An example schedule, written as `--rollout-steps` takes it.
const rolloutStepsExample = '1:4h,10:12h,50:24h,100';

/// Help for `--rollout-steps`, on a command that puts [subject] on a track.
String rolloutStepsHelp(String subject) =>
    'A timed rollout schedule to raise $subject through, written as '
    '<percentage>:<duration> steps from $minRolloutSteps to $maxRolloutSteps '
    'of them, ending at 100 with no duration '
    '(e.g. "$rolloutStepsExample"). Durations are whole minutes, hours or '
    'days ("30m", "12h", "2d"). The server advances the rollout step by '
    'step, and timed schedules need an Enterprise plan. Mutually exclusive '
    'with --$rolloutArgName.';

/// Help for `--pause-weekends`.
const pauseWeekendsHelp =
    'Hold the rollout at its current step over Saturday and Sunday instead of '
    'advancing. Only applies with --$rolloutStepsArgName.';

/// Help for `--timezone`.
const timezoneHelp =
    'The IANA time zone name whose clock and weekends the rollout schedule '
    'follows (e.g. "America/New_York"). Defaults to UTC. Only applies with '
    '--$rolloutStepsArgName.';

/// {@template rollout_schedule}
/// A timed rollout schedule asked for on the command line.
/// {@endtemplate}
@immutable
class RolloutSchedule {
  /// {@macro rollout_schedule}
  const RolloutSchedule({
    required this.steps,
    this.pauseWeekends = false,
    this.timezone,
  });

  /// The steps to raise the rollout through, in increasing order of
  /// percentage, ending at 100.
  final List<RolloutStep> steps;

  /// Whether the rollout holds its step over weekends in [timezone].
  final bool pauseWeekends;

  /// The IANA time zone name whose clock and weekends the schedule follows,
  /// or null to leave that to the server.
  final String? timezone;

  /// The percentage the rollout starts at, which the first step sets.
  double get initialPercentage => steps.first.percentage;

  @override
  int get hashCode => Object.hashAll([
    listHash(steps),
    pauseWeekends,
    timezone,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RolloutSchedule &&
        listsEqual(steps, other.steps) &&
        pauseWeekends == other.pauseWeekends &&
        timezone == other.timezone;
  }
}

/// Reads `--rollout-steps`, `--pause-weekends` and `--timezone` from
/// [results].
///
/// Returns a null schedule when `--rollout-steps` was not given. The error
/// names the first problem: a schedule that does not parse, a flag that only
/// qualifies a schedule given without one, or `--[percentageArgName]` given
/// alongside a schedule.
({RolloutSchedule? schedule, String? error}) readRolloutSchedule(
  ArgResults results, {
  required String percentageArgName,
}) {
  final pauseWeekends = results[pauseWeekendsArgName] == true;
  final timezone = (results[timezoneArgName] as String?)?.trim();

  if (results[rolloutStepsArgName] case final String stepsArg) {
    if (results[percentageArgName] != null) {
      return (
        schedule: null,
        error:
            '--$percentageArgName and --$rolloutStepsArgName are mutually '
            'exclusive: a rollout is either a fixed percentage or a '
            'schedule.',
      );
    }
    final (:steps, error: stepsError) = parseRolloutSteps(
      stepsArg,
      argName: rolloutStepsArgName,
    );
    if (steps == null) return (schedule: null, error: stepsError);
    if (timezone != null) {
      final timezoneError = rolloutTimezoneError(
        timezone,
        argName: timezoneArgName,
      );
      if (timezoneError != null) return (schedule: null, error: timezoneError);
    }
    return (
      schedule: RolloutSchedule(
        steps: steps,
        pauseWeekends: pauseWeekends,
        timezone: timezone,
      ),
      error: null,
    );
  }

  final strandedArgName = pauseWeekends
      ? pauseWeekendsArgName
      : timezone != null
      ? timezoneArgName
      : null;
  if (strandedArgName != null) {
    return (
      schedule: null,
      error:
          '--$strandedArgName only applies to a timed rollout schedule, '
          'which --$rolloutStepsArgName sets (e.g. '
          '--$rolloutStepsArgName=$rolloutStepsExample).',
    );
  }
  return (schedule: null, error: null);
}

/// How many minutes each duration suffix `--rollout-steps` accepts stands
/// for, largest unit first so [formatRolloutStepDuration] prefers it.
const _durationUnitMinutes = {'d': 60 * 24, 'h': 60, 'm': 1};

/// A step's duration: a whole number of minutes, hours or days.
final _durationPattern = RegExp(r'^(\d+)([mhd])$');

/// Parses [value], the argument to `--[argName]`, as a timed rollout
/// schedule: `<percentage>:<duration>` steps separated by commas, ending at
/// 100 with no duration.
///
/// Returns the steps, or an error naming the flag and what is wrong with it.
({List<RolloutStep>? steps, String? error}) parseRolloutSteps(
  String value, {
  required String argName,
}) {
  ({List<RolloutStep>? steps, String? error}) fail(String reason) =>
      (steps: null, error: '--$argName $reason');

  final entries = value.split(',').map((entry) => entry.trim()).toList();
  if (entries.length < minRolloutSteps || entries.length > maxRolloutSteps) {
    return fail(
      'takes $minRolloutSteps to $maxRolloutSteps steps '
      '(got ${entries.length} in "$value").',
    );
  }

  final steps = <RolloutStep>[];
  for (final (index, entry) in entries.indexed) {
    final isLast = index == entries.length - 1;
    final parts = entry.split(':');
    if (parts.length > 2 || parts.any((part) => part.isEmpty)) {
      return fail(
        'steps are written as <percentage>:<duration>, such as 10:12h '
        '(got "$entry").',
      );
    }

    final (:percentage, error: _) = parseRolloutPercentage(
      parts.first,
      argName: argName,
    );
    if (percentage == null) {
      return fail(
        'percentages must be greater than 0 and at most 100, with at most '
        'two decimal places (got "${parts.first}").',
      );
    }
    if (steps.isNotEmpty && percentage <= steps.last.percentage) {
      return fail(
        'percentages must increase step by step (got '
        '"${formatRolloutArgument(steps.last.percentage)}" then '
        '"${formatRolloutArgument(percentage)}").',
      );
    }
    if (isLast && percentage != 100) {
      return fail(
        'must end at 100, which is where the rollout stops '
        '(got "${formatRolloutArgument(percentage)}").',
      );
    }

    final duration = parts.length == 2 ? parts.last : null;
    if (isLast && duration != null) {
      return fail(
        'takes no duration on its last step, which the rollout stays at '
        '(got "$entry").',
      );
    }
    if (!isLast && duration == null) {
      return fail(
        'needs a duration on every step but the last, such as '
        '"$rolloutStepsExample" (got "$entry").',
      );
    }

    int? durationMinutes;
    if (duration != null) {
      durationMinutes = _durationInMinutes(duration);
      if (durationMinutes == null) {
        return fail(
          'durations are a whole number of minutes, hours or days above '
          'zero, such as "30m", "12h" or "2d" (got "$duration").',
        );
      }
    }

    steps.add(
      RolloutStep(percentage: percentage, durationMinutes: durationMinutes),
    );
  }

  return (steps: steps, error: null);
}

/// [duration] in minutes, or null when it is not a whole number of minutes,
/// hours or days above zero.
int? _durationInMinutes(String duration) {
  final match = _durationPattern.firstMatch(duration);
  if (match == null) return null;
  final unitMinutes = _durationUnitMinutes[match.group(2)] ?? 0;
  final minutes = int.parse(match.group(1) ?? '0') * unitMinutes;
  return minutes > 0 ? minutes : null;
}

/// A time zone name's shape: slash-separated words, as `America/New_York`.
/// Whether the zone exists is the server's call.
final _timezonePattern = RegExp(r'^[A-Za-z][\w+-]*(/[\w+-]+)*$');

/// Returns an error when [value], the argument to `--[argName]`, is not
/// shaped like an IANA time zone name, and null when it is.
String? rolloutTimezoneError(String value, {required String argName}) {
  if (_timezonePattern.hasMatch(value)) return null;
  return '--$argName must be an IANA time zone name, such as '
      'America/New_York (got "$value").';
}

/// Describes [schedule] in one line, as
/// `1% for 4h, then 10% for 12h, then 100%`.
String formatRolloutSchedule(RolloutSchedule schedule) {
  final steps = schedule.steps.map((step) {
    final percentage = formatRolloutPercentage(step.percentage);
    final minutes = step.durationMinutes;
    return minutes == null
        ? percentage
        : '$percentage for ${formatRolloutStepDuration(minutes)}';
  });
  final weekends = schedule.pauseWeekends
      ? ', holding over weekends in ${schedule.timezone ?? 'UTC'}'
      : '';
  return '${steps.join(', then ')}$weekends';
}

/// Formats [schedule]'s steps as `--rollout-steps` takes them, e.g.
/// `1:4h,10:12h,100`.
String formatRolloutStepsArgument(RolloutSchedule schedule) => schedule.steps
    .map((step) {
      final percentage = formatRolloutArgument(step.percentage);
      final minutes = step.durationMinutes;
      return minutes == null
          ? percentage
          : '$percentage:${formatRolloutStepDuration(minutes)}';
    })
    .join(',');

/// `--rollout-steps` and the flags that qualify it, as they were given, for
/// a command line a reader can copy.
List<String> rolloutScheduleArguments(RolloutSchedule schedule) => [
  '--$rolloutStepsArgName ${formatRolloutStepsArgument(schedule)}',
  if (schedule.pauseWeekends) '--$pauseWeekendsArgName',
  if (schedule.timezone case final timezone?) '--$timezoneArgName $timezone',
];

/// The command that puts the rollout of patch [patchNumber] on release
/// [releaseVersion] on [schedule]. [appId] and [flavor] are passed through
/// when given.
String scheduleRolloutCommand({
  required String releaseVersion,
  required int patchNumber,
  required RolloutSchedule schedule,
  String? appId,
  String? flavor,
}) => [
  'shorebird patches rollout',
  '--release-version $releaseVersion',
  '--patch-number $patchNumber',
  if (appId != null) '--app-id $appId',
  if (flavor != null) '--flavor $flavor',
  ...rolloutScheduleArguments(schedule),
].join(' ');

/// Formats [minutes] as it is written on the command line, in the largest
/// unit that divides it evenly, e.g. `2d`, `12h` or `30m`.
String formatRolloutStepDuration(int minutes) {
  for (final MapEntry(key: suffix, value: unitMinutes)
      in _durationUnitMinutes.entries) {
    if (minutes % unitMinutes == 0) return '${minutes ~/ unitMinutes}$suffix';
  }
  return '${minutes}m';
}
