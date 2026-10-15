import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MetricsUsersCommand, () {
    final harness = MetricsTestHarness();
    final response = GetUniqueUsersResponse(
      asOf: DateTime.utc(2026, 10, 15),
      granularity: 'day',
      current: UniqueUsersCurrentWindow(
        uniqueUsers: 40,
        range: metricsTestRange,
        timeSeries: [
          UniqueUsersTimeSeriesEntry(
            period: DateTime.utc(2026, 10),
            uniqueUsers: 12,
          ),
        ],
        breakdown: const [
          UniqueUsersBreakdownEntry(
            groupBy: 'release_version',
            groupValue: '1.0.0+1',
            uniqueUsers: 30,
          ),
          UniqueUsersBreakdownEntry(
            groupBy: 'release_version',
            groupValue: '',
            uniqueUsers: 10,
          ),
        ],
      ),
      previous: UniqueUsersWindow(
        uniqueUsers: 35,
        range: MetricsRange(
          start: DateTime.utc(2026, 8, 20),
          end: DateTime.utc(2026, 9, 17),
        ),
      ),
    );

    late MetricsUsersCommand command;

    setUpAll(() {
      registerFallbackValue(DateTime(2026));
    });

    setUp(() {
      harness.setUp();
      command = harness.createCommand(MetricsUsersCommand.new);
      when(
        () => harness.codePushClient.getUniqueUsers(
          appId: any(named: 'appId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenAnswer((_) async => response);
    });

    test('has the correct name and description', () {
      expect(command.name, equals('users'));
      expect(command.description, contains('unique devices'));
    });

    test('passes the window, granularity and group-by', () async {
      harness.args['start'] = '2026-09-01T00:00:00Z';
      harness.args['granularity'] = 'day';
      harness.args['group-by'] = 'release_version';

      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getUniqueUsers(
          appId: metricsTestAppId,
          start: DateTime.utc(2026, 9),
          granularity: 'day',
          groupBy: 'release_version',
        ),
      ).called(1);
    });

    const previousLine =
        '  Previous window: 35 '
        '(2026-08-20T00:00:00Z to 2026-09-17T00:00:00Z)';

    test('prints totals, time series and breakdown', () async {
      await harness.run(command.run);

      expect(
        loggedLines(harness),
        equals([
          'Unique users: 40',
          '  Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z',
          previousLine,
          'Time series (day):',
          '  2026-10-01T00:00:00Z  12',
          'By release_version:',
          '  1.0.0+1    30',
          '  (unknown)  10',
        ]),
      );
    });

    test('omits absent sections', () async {
      when(
        () => harness.codePushClient.getUniqueUsers(
          appId: any(named: 'appId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenAnswer(
        (_) async => GetUniqueUsersResponse(
          asOf: DateTime.utc(2026, 10, 15),
          granularity: null,
          current: UniqueUsersCurrentWindow(
            uniqueUsers: 4,
            range: metricsTestRange,
          ),
          previous: null,
        ),
      );

      await harness.run(command.run);

      expect(
        loggedLines(harness),
        equals([
          'Unique users: 4',
          '  Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z',
        ]),
      );
    });

    test('emits the response with --json', () async {
      final (:exitCode, :json) = await harness.runJson(command);
      expect(json['data'], equals(response.toJson()));
    });
  });
}
