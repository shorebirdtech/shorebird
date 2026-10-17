import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/patches/patches.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../metrics/metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  final response = GetPatchMetricResponse(
    asOf: DateTime.utc(2026, 10, 15),
    granularity: 'week',
    current: PatchMetricCurrentWindow(
      count: 30,
      range: metricsTestRange,
      timeSeries: const [],
      breakdown: const [],
    ),
    previous: PatchMetricWindow(count: 18, range: metricsTestRange),
  );

  final harness = MetricsTestHarness();

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(harness.setUp);

  group(PatchesStatsCommand, () {
    late PatchesStatsCommand command;

    setUp(() {
      command = harness.createCommand(PatchesStatsCommand.new);
      when(
        () => harness.codePushClient.getAppPatchInstalls(
          appId: any(named: 'appId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenAnswer((_) async => response);
    });

    test('is a hidden command named stats', () {
      expect(command.name, equals('stats'));
      expect(command.hidden, isTrue);
    });

    test('runs metrics installs', () async {
      final result = await harness.run(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => harness.codePushClient.getAppPatchInstalls(
          appId: metricsTestAppId,
        ),
      ).called(1);
    });
  });
}
