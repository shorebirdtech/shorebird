import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MetricsVersionsCommand, () {
    final harness = MetricsTestHarness();
    final response = GetVersionDistributionResponse(
      entries: const [
        VersionDistributionEntry(
          releaseVersion: '1.0.1+2',
          deviceCount: 75,
          percentage: .75,
        ),
        VersionDistributionEntry(
          releaseVersion: null,
          deviceCount: 25,
          percentage: .25,
        ),
      ],
      totalDevices: 100,
      activeWindowDays: 28,
      asOf: DateTime.utc(2026, 10, 15),
    );

    late MetricsVersionsCommand command;

    setUp(() {
      harness.setUp();
      command = harness.createCommand(MetricsVersionsCommand.new);
      when(
        () => harness.codePushClient.getVersionDistribution(
          appId: any(named: 'appId'),
        ),
      ).thenAnswer((_) async => response);
    });

    test('has the correct name and description', () {
      expect(command.name, equals('versions'));
      expect(command.description, contains('release versions'));
    });

    test('prints one line per version', () async {
      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getVersionDistribution(
          appId: metricsTestAppId,
        ),
      ).called(1);
      expect(
        loggedLines(harness),
        equals([
          'Active devices in the last 28 days: 100',
          '  1.0.1+2    75  75.0%',
          '  (unknown)  25  25.0%',
        ]),
      );
    });

    test('emits the response with --json', () async {
      final (:exitCode, :json) = await harness.runJson(command);
      expect(json['data'], equals(response.toJson()));
    });
  });
}
