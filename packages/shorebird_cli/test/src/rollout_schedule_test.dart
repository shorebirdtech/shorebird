import 'package:args/args.dart';
import 'package:shorebird_cli/src/rollout_percentage.dart';
import 'package:shorebird_cli/src/rollout_schedule.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();

  group('parseRolloutSteps', () {
    ({List<RolloutStep>? steps, String? error}) parse(String value) =>
        parseRolloutSteps(value, argName: rolloutStepsArgName);

    test('reads percentages and durations', () {
      expect(
        parse('1:4h,10:12h,50:30m,75:2d,100').steps,
        equals(const [
          RolloutStep(percentage: 1, durationMinutes: 240),
          RolloutStep(percentage: 10, durationMinutes: 720),
          RolloutStep(percentage: 50, durationMinutes: 30),
          RolloutStep(percentage: 75, durationMinutes: 2880),
          RolloutStep(percentage: 100),
        ]),
      );
    });

    test('ignores whitespace around steps', () {
      expect(parse(' 10:12h , 100 ').steps, hasLength(2));
    });

    test('keeps fractional percentages', () {
      expect(
        parse('0.5:1h,100').steps?.first,
        equals(const RolloutStep(percentage: 0.5, durationMinutes: 60)),
      );
    });

    test('rejects a single step', () {
      expect(
        parse('100').error,
        equals(
          '--$rolloutStepsArgName takes $minRolloutSteps to $maxRolloutSteps '
          'steps (got 1 in "100").',
        ),
      );
    });

    test('rejects more steps than the server takes', () {
      final steps = [
        for (var i = 1; i < maxRolloutSteps + 1; i++) '$i:1h',
        '100',
      ].join(',');

      expect(
        parse(steps).error,
        contains('takes $minRolloutSteps to $maxRolloutSteps steps'),
      );
    });

    test('rejects a step that is not a percentage and a duration', () {
      expect(
        parse('10:12h:30m,100').error,
        equals(
          '--$rolloutStepsArgName steps are written as '
          '<percentage>:<duration>, such as 10:12h (got "10:12h:30m").',
        ),
      );
      expect(parse(':12h,100').error, contains('steps are written as'));
      expect(parse('10:,100').error, contains('steps are written as'));
    });

    test('rejects a percentage outside 0 to 100', () {
      expect(
        parse('0:1h,100').error,
        equals(
          '--$rolloutStepsArgName percentages must be greater than 0 and at '
          'most 100, with at most two decimal places (got "0").',
        ),
      );
      expect(parse('10:1h,101').error, contains('percentages must be'));
      expect(parse('10.555:1h,100').error, contains('percentages must be'));
    });

    test('rejects percentages that do not increase', () {
      expect(
        parse('10:1h,10:2h,100').error,
        equals(
          '--$rolloutStepsArgName percentages must increase step by step '
          '(got "10" then "10").',
        ),
      );
      expect(
        parse('50:1h,10:2h,100').error,
        contains('percentages must increase step by step'),
      );
    });

    test('rejects a schedule that does not end at 100', () {
      expect(
        parse('10:1h,50').error,
        equals(
          '--$rolloutStepsArgName must end at 100, which is where the '
          'rollout stops (got "50").',
        ),
      );
    });

    test('rejects a duration on the last step', () {
      expect(
        parse('10:1h,100:2h').error,
        equals(
          '--$rolloutStepsArgName takes no duration on its last step, which '
          'the rollout stays at (got "100:2h").',
        ),
      );
    });

    test('rejects a step before the last without a duration', () {
      expect(
        parse('10,100').error,
        equals(
          '--$rolloutStepsArgName needs a duration on every step but the '
          'last, such as "$rolloutStepsExample" (got "10").',
        ),
      );
    });

    for (final duration in ['0h', '12', '12hours', 'h', '1.5h', '-1h', '30s']) {
      test('rejects the duration "$duration"', () {
        expect(
          parse('10:$duration,100').error,
          equals(
            '--$rolloutStepsArgName durations are a whole number of minutes, '
            'hours or days above zero, such as "30m", "12h" or "2d" '
            '(got "$duration").',
          ),
        );
      });
    }
  });

  group('rolloutTimezoneError', () {
    String? error(String value) =>
        rolloutTimezoneError(value, argName: timezoneArgName);

    for (final value in [
      'UTC',
      'America/New_York',
      'America/Argentina/Buenos_Aires',
      'Etc/GMT+5',
    ]) {
      test('accepts "$value"', () => expect(error(value), isNull));
    }

    for (final value in ['', 'New York', '/America', 'America/', '1America']) {
      test('rejects "$value"', () {
        expect(
          error(value),
          equals(
            '--$timezoneArgName must be an IANA time zone name, such as '
            'America/New_York (got "$value").',
          ),
        );
      });
    }
  });

  group('readRolloutSchedule', () {
    late ArgParser parser;

    setUp(() {
      parser = ArgParser()
        ..addOption(rolloutArgName)
        ..addOption(rolloutStepsArgName)
        ..addFlag(pauseWeekendsArgName, negatable: false)
        ..addOption(timezoneArgName);
    });

    ({RolloutSchedule? schedule, String? error}) read(List<String> args) =>
        readRolloutSchedule(
          parser.parse(args),
          percentageArgName: rolloutArgName,
        );

    test('returns no schedule when no flags are given', () {
      final (:schedule, :error) = read([]);
      expect(schedule, isNull);
      expect(error, isNull);
    });

    test('returns the schedule, weekend pause and timezone', () {
      final (:schedule, :error) = read([
        '--$rolloutStepsArgName=1:4h,100',
        '--$pauseWeekendsArgName',
        '--$timezoneArgName=America/New_York',
      ]);

      expect(error, isNull);
      expect(
        schedule,
        equals(
          const RolloutSchedule(
            steps: [
              RolloutStep(percentage: 1, durationMinutes: 240),
              RolloutStep(percentage: 100),
            ],
            pauseWeekends: true,
            timezone: 'America/New_York',
          ),
        ),
      );
      expect(schedule?.initialPercentage, equals(1));
    });

    test('reports a schedule given with a percentage', () {
      final (:schedule, :error) = read([
        '--$rolloutArgName=10',
        '--$rolloutStepsArgName=1:4h,100',
      ]);

      expect(schedule, isNull);
      expect(
        error,
        equals(
          '--$rolloutArgName and --$rolloutStepsArgName are mutually '
          'exclusive: a rollout is either a fixed percentage or a schedule.',
        ),
      );
    });

    test('reports a schedule that does not parse', () {
      final (:schedule, :error) = read(['--$rolloutStepsArgName=1:4h']);

      expect(schedule, isNull);
      expect(error, contains('takes $minRolloutSteps to $maxRolloutSteps'));
    });

    test('reports a timezone that is not a zone name', () {
      final (:schedule, :error) = read([
        '--$rolloutStepsArgName=1:4h,100',
        '--$timezoneArgName=New York',
      ]);

      expect(schedule, isNull);
      expect(error, contains('must be an IANA time zone name'));
    });

    for (final argName in [pauseWeekendsArgName, timezoneArgName]) {
      test('reports --$argName given without a schedule', () {
        final (:schedule, :error) = read([
          if (argName == timezoneArgName) '--$argName=UTC' else '--$argName',
        ]);

        expect(schedule, isNull);
        expect(
          error,
          equals(
            '--$argName only applies to a timed rollout schedule, which '
            '--$rolloutStepsArgName sets (e.g. '
            '--$rolloutStepsArgName=$rolloutStepsExample).',
          ),
        );
      });
    }
  });

  group('formatRolloutSchedule', () {
    test('reads as a sequence of holds', () {
      expect(
        formatRolloutSchedule(
          const RolloutSchedule(
            steps: [
              RolloutStep(percentage: 1, durationMinutes: 240),
              RolloutStep(percentage: 12.5, durationMinutes: 30),
              RolloutStep(percentage: 100),
            ],
          ),
        ),
        equals('1% for 4h, then 12.5% for 30m, then 100%'),
      );
    });

    test('says where weekends are held', () {
      expect(
        formatRolloutSchedule(
          const RolloutSchedule(
            steps: [
              RolloutStep(percentage: 1, durationMinutes: 2880),
              RolloutStep(percentage: 100),
            ],
            pauseWeekends: true,
            timezone: 'America/New_York',
          ),
        ),
        equals(
          '1% for 2d, then 100%, holding over weekends in '
          'America/New_York',
        ),
      );
    });

    test('says UTC when weekends are held without a timezone', () {
      expect(
        formatRolloutSchedule(
          const RolloutSchedule(
            steps: [
              RolloutStep(percentage: 1, durationMinutes: 60),
              RolloutStep(percentage: 100),
            ],
            pauseWeekends: true,
          ),
        ),
        endsWith('holding over weekends in UTC'),
      );
    });
  });

  group('formatRolloutStepsArgument', () {
    test('writes steps --$rolloutStepsArgName reads back', () {
      final (:steps, error: _) = parseRolloutSteps(
        rolloutStepsExample,
        argName: rolloutStepsArgName,
      );
      final written = formatRolloutStepsArgument(
        RolloutSchedule(steps: steps!),
      );

      // 24h is written back in the largest unit that fits it, as 1d.
      expect(written, equals('1:4h,10:12h,50:1d,100'));
      expect(
        parseRolloutSteps(written, argName: rolloutStepsArgName).steps,
        equals(steps),
      );
    });
  });

  group('formatRolloutStepDuration', () {
    for (final (minutes, expected) in [
      (30, '30m'),
      (60, '1h'),
      (90, '90m'),
      (720, '12h'),
      (1440, '1d'),
      (2880, '2d'),
    ]) {
      test('formats $minutes minutes as $expected', () {
        expect(formatRolloutStepDuration(minutes), equals(expected));
      });
    }
  });

  group(RolloutSchedule, () {
    test('is equatable', () {
      const schedule = RolloutSchedule(
        steps: [
          RolloutStep(percentage: 1, durationMinutes: 240),
          RolloutStep(percentage: 100),
        ],
        timezone: 'UTC',
      );

      expect(
        schedule,
        equals(
          const RolloutSchedule(
            steps: [
              RolloutStep(percentage: 1, durationMinutes: 240),
              RolloutStep(percentage: 100),
            ],
            timezone: 'UTC',
          ),
        ),
      );
      expect(
        schedule.hashCode,
        equals(
          const RolloutSchedule(
            steps: [
              RolloutStep(percentage: 1, durationMinutes: 240),
              RolloutStep(percentage: 100),
            ],
            timezone: 'UTC',
          ).hashCode,
        ),
      );
      expect(
        schedule,
        isNot(
          equals(
            const RolloutSchedule(
              steps: [
                RolloutStep(percentage: 1, durationMinutes: 240),
                RolloutStep(percentage: 100),
              ],
              timezone: 'America/New_York',
            ),
          ),
        ),
      );
      expect(
        schedule,
        isNot(
          equals(
            const RolloutSchedule(
              steps: [RolloutStep(percentage: 100)],
              timezone: 'UTC',
            ),
          ),
        ),
      );
    });
  });
}
