import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MetricsActiveHoursCommand, () {
    final harness = MetricsTestHarness();

    GetActiveHoursResponse responseWith({
      required int? windowStart,
      required int? busiest,
    }) => GetActiveHoursResponse(
      hourly: [
        for (var hour = 0; hour < 24; hour++)
          ActiveHourEntry(hourUtc: hour, averageActiveDevices: hour * 1.5),
      ],
      recommendedWindowStartUtc: windowStart,
      recommendedWindowLengthHours: 2,
      busiestHourUtc: busiest,
      lookbackDays: 28,
      asOf: DateTime.utc(2026, 10, 15),
    );

    late MetricsActiveHoursCommand command;

    void stub(GetActiveHoursResponse response) {
      when(
        () => harness.codePushClient.getActiveHours(appId: any(named: 'appId')),
      ).thenAnswer((_) async => response);
    }

    setUp(() {
      harness.setUp();
      command = harness.createCommand(MetricsActiveHoursCommand.new);
      stub(responseWith(windowStart: 23, busiest: 14));
    });

    test('has the correct name and description', () {
      expect(command.name, equals('active-hours'));
      expect(command.description, contains('each hour of the day'));
    });

    test('prints each hour and the recommendation', () async {
      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getActiveHours(appId: metricsTestAppId),
      ).called(1);
      final lines = loggedLines(harness);
      expect(lines, hasLength(27));
      expect(
        lines.first,
        equals('Average active devices by hour (UTC) over the last 28 days:'),
      );
      expect(lines[1], equals('  00:00  0.0'));
      expect(lines[24], equals('  23:00  34.5'));
      expect(
        lines[25],
        equals('Recommended release window: 23:00 to 01:00 UTC'),
      );
      expect(lines[26], equals('Busiest hour: 14:00 UTC'));
    });

    test('says when there is not enough data', () async {
      stub(responseWith(windowStart: null, busiest: null));

      await harness.run(command.run);

      expect(
        loggedLines(harness).last,
        equals('Not enough data yet to recommend a release window.'),
      );
    });

    test('emits the response with --json', () async {
      final (:exitCode, :json) = await harness.runJson(command);
      expect(
        json['data'],
        equals(responseWith(windowStart: 23, busiest: 14).toJson()),
      );
    });
  });
}
