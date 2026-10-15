import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MetricsAdoptionCommand, () {
    final harness = MetricsTestHarness();
    final response = GetPatchAdoptionResponse(
      releaseVersion: '1.0.0+1',
      isLatest: true,
      granularity: null,
      range: metricsTestRange,
      asOf: DateTime.utc(2026, 10, 15),
      patches: const [
        PatchAdoptionEntry(
          patchNumber: 1,
          targetPlatforms: [ReleasePlatform.android, ReleasePlatform.ios],
          isRolledBack: false,
          series: [
            PatchAdoptionPoint(
              period: null,
              devices: 2310,
              target: 2500,
              adoptionPct: .924,
            ),
          ],
        ),
        PatchAdoptionEntry(
          patchNumber: 2,
          targetPlatforms: [ReleasePlatform.android],
          isRolledBack: true,
          series: [
            PatchAdoptionPoint(
              period: null,
              devices: 10,
              target: 2500,
              adoptionPct: .004,
            ),
          ],
        ),
      ],
    );

    late MetricsAdoptionCommand command;

    void stub(GetPatchAdoptionResponse response) {
      when(
        () => harness.codePushClient.getPatchAdoption(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
        ),
      ).thenAnswer((_) async => response);
    }

    setUpAll(() {
      registerFallbackValue(DateTime(2026));
    });

    setUp(() {
      harness.setUp();
      command = harness.createCommand(MetricsAdoptionCommand.new);
      stub(response);
    });

    test('has the correct name and description', () {
      expect(command.name, equals('adoption'));
      expect(command.description, contains('patches'));
    });

    test('passes --release-version through without a lookup', () async {
      harness.args['release-version'] = '1.0.0+1';
      harness.args['granularity'] = 'day';
      harness.args['end'] = '2026-10-10';

      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getPatchAdoption(
          appId: metricsTestAppId,
          releaseVersion: '1.0.0+1',
          end: DateTime.utc(2026, 10, 10),
          granularity: 'day',
        ),
      ).called(1);
      verifyNever(
        () => harness.codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      );
    });

    test('prints one line per patch', () async {
      await harness.run(command.run);

      expect(
        loggedLines(harness),
        equals([
          'Patch adoption for release 1.0.0+1 (latest release)',
          '  Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z',
          '  #1  android, ios  92.4%  (2310 of 2500 devices)',
          '  #2  android  0.4%  (10 of 2500 devices)  [rolled back]',
        ]),
      );
    });

    test('prints a series per patch with --granularity', () async {
      stub(
        GetPatchAdoptionResponse(
          releaseVersion: '1.0.0+1',
          isLatest: false,
          granularity: 'day',
          range: metricsTestRange,
          asOf: DateTime.utc(2026, 10, 15),
          patches: [
            PatchAdoptionEntry(
              patchNumber: 1,
              targetPlatforms: const [ReleasePlatform.ios],
              isRolledBack: false,
              series: [
                PatchAdoptionPoint(
                  period: DateTime.utc(2026, 10),
                  devices: 1,
                  target: 4,
                  adoptionPct: .25,
                ),
                PatchAdoptionPoint(
                  period: DateTime.utc(2026, 10, 2),
                  devices: 2,
                  target: 4,
                  adoptionPct: .5,
                ),
              ],
            ),
          ],
        ),
      );

      await harness.run(command.run);

      expect(
        loggedLines(harness),
        equals([
          'Patch adoption for release 1.0.0+1',
          '  Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z',
          '  #1  ios',
          '    2026-10-01T00:00:00Z  25.0%  (1 of 4 devices)',
          '    2026-10-02T00:00:00Z  50.0%  (2 of 4 devices)',
        ]),
      );
    });

    test('says when the release has no patches', () async {
      stub(
        GetPatchAdoptionResponse(
          releaseVersion: '1.0.0+1',
          isLatest: true,
          granularity: null,
          range: metricsTestRange,
          asOf: DateTime.utc(2026, 10, 15),
          patches: const [],
        ),
      );

      await harness.run(command.run);

      expect(loggedLines(harness).last, equals('  No patches found.'));
    });

    test('emits the response with --json', () async {
      final (:exitCode, :json) = await harness.runJson(command);
      expect(json['data'], equals(response.toJson()));
    });
  });
}
