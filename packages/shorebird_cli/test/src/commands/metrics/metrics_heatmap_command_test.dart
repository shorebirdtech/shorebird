import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MetricsHeatmapCommand, () {
    final harness = MetricsTestHarness();

    GetActivityHeatmapResponse responseWith({
      required int? busiestDay,
      required int? busiestHour,
    }) => GetActivityHeatmapResponse(
      cells: const [
        ActivityHeatmapCell(
          dayOfWeekUtc: 1,
          hourUtc: 0,
          averageActiveDevices: 1234.4,
        ),
        ActivityHeatmapCell(
          dayOfWeekUtc: 7,
          hourUtc: 23,
          averageActiveDevices: 5.6,
        ),
        // Out of range; ignored.
        ActivityHeatmapCell(
          dayOfWeekUtc: 8,
          hourUtc: 0,
          averageActiveDevices: 99,
        ),
      ],
      busiestDayOfWeekUtc: busiestDay,
      busiestHourUtc: busiestHour,
      lookbackDays: 28,
      asOf: DateTime.utc(2026, 10, 15),
    );

    late MetricsHeatmapCommand command;

    void stub(GetActivityHeatmapResponse response) {
      when(
        () => harness.codePushClient.getActivityHeatmap(
          appId: any(named: 'appId'),
        ),
      ).thenAnswer((_) async => response);
    }

    setUp(() {
      harness.setUp();
      command = harness.createCommand(MetricsHeatmapCommand.new);
      stub(responseWith(busiestDay: 2, busiestHour: 14));
    });

    test('has the correct name and description', () {
      expect(command.name, equals('heatmap'));
      expect(command.description, contains('day of the week'));
    });

    test('prints a day-by-hour grid and the busiest hour', () async {
      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getActivityHeatmap(
          appId: metricsTestAppId,
        ),
      ).called(1);
      final lines = loggedLines(harness);
      expect(lines, hasLength(10));
      expect(lines[1], startsWith('         00   01   02 '));
      expect(lines[2], startsWith('  Sun  1234    0    0 '));
      expect(lines[8], startsWith('  Sat     0    0 '));
      expect(lines[8], endsWith('    6'));
      expect(lines.last, equals('Busiest: Mon 14:00 UTC'));
    });

    test('says when there is not enough data', () async {
      stub(responseWith(busiestDay: null, busiestHour: null));

      await harness.run(command.run);

      expect(
        loggedLines(harness).last,
        equals('Not enough data yet to find the busiest hour.'),
      );
    });

    test('emits the response with --json', () async {
      final (:exitCode, :json) = await harness.runJson(command);
      expect(
        json['data'],
        equals(responseWith(busiestDay: 2, busiestHour: 14).toJson()),
      );
    });
  });
}
