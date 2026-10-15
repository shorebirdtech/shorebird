import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MetricsNewDevicesCommand, () {
    final harness = MetricsTestHarness();
    final response = GetNewDevicesResponse(
      current: 95,
      previous: 87,
      windowDays: 28,
      asOf: DateTime.utc(2026, 10, 15),
    );

    late MetricsNewDevicesCommand command;

    void stub(GetNewDevicesResponse response) {
      when(
        () => harness.codePushClient.getNewDevices(appId: any(named: 'appId')),
      ).thenAnswer((_) async => response);
    }

    setUp(() {
      harness.setUp();
      command = harness.createCommand(MetricsNewDevicesCommand.new);
      stub(response);
    });

    test('has the correct name and description', () {
      expect(command.name, equals('new-devices'));
      expect(command.description, contains('first time'));
    });

    test('prints the current and previous counts', () async {
      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getNewDevices(appId: metricsTestAppId),
      ).called(1);
      expect(
        loggedLines(harness),
        equals([
          'New devices in the last 28 days: 95',
          '  Previous 28 days: 87',
        ]),
      );
    });

    test('says when the previous window is unavailable', () async {
      stub(
        GetNewDevicesResponse(
          current: 95,
          previous: null,
          windowDays: 28,
          asOf: DateTime.utc(2026, 10, 15),
        ),
      );

      await harness.run(command.run);

      expect(
        loggedLines(harness).last,
        equals(
          '  Previous 28 days: unavailable (before metrics were recorded)',
        ),
      );
    });

    test('emits the response with --json', () async {
      final (:exitCode, :json) = await harness.runJson(command);
      expect(json['data'], equals(response.toJson()));
    });
  });
}
