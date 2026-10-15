import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  final release = Release(
    id: 7,
    appId: metricsTestAppId,
    version: '1.0.0+1',
    flutterRevision: 'abc',
    flutterVersion: '3.27.0',
    displayName: '1.0.0+1',
    platformStatuses: const {},
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final response = GetPatchMetricResponse(
    asOf: DateTime.utc(2026, 10, 15),
    granularity: 'week',
    current: PatchMetricCurrentWindow(
      count: 30,
      range: metricsTestRange,
      timeSeries: [
        PatchMetricTimeSeriesEntry(period: DateTime.utc(2026, 9, 21), count: 5),
        PatchMetricTimeSeriesEntry(
          period: DateTime.utc(2026, 9, 28),
          count: 25,
        ),
      ],
      breakdown: const [
        PatchMetricBreakdownEntry(
          groupBy: 'release',
          groupValue: '1.0.0+1',
          count: 20,
        ),
        PatchMetricBreakdownEntry(
          groupBy: 'release',
          groupValue: '1.0.1+2',
          count: 10,
        ),
      ],
    ),
    previous: PatchMetricWindow(
      count: 18,
      range: MetricsRange(
        start: DateTime.utc(2026, 8, 20),
        end: DateTime.utc(2026, 9, 17),
      ),
    ),
  );

  final harness = MetricsTestHarness();

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    harness.setUp();
    when(
      () => harness.codePushClientWrapper.maybeGetRelease(
        appId: any(named: 'appId'),
        releaseVersion: any(named: 'releaseVersion'),
      ),
    ).thenAnswer((_) async => release);
  });

  group(MetricsInstallsCommand, () {
    late MetricsInstallsCommand command;

    setUp(() {
      command = harness.createCommand(MetricsInstallsCommand.new);
      when(
        () => harness.codePushClient.getAppPatchInstalls(
          appId: any(named: 'appId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenAnswer((_) async => response);
      when(
        () => harness.codePushClient.getReleasePatchInstalls(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenAnswer((_) async => response);
    });

    test('has the correct name and description', () {
      expect(command.name, equals('installs'));
      expect(command.description, contains('installed'));
      expect(command.description, contains('--json'));
    });

    test('queries app-wide installs with granularity and group-by', () async {
      harness.args['granularity'] = 'week';
      harness.args['group-by'] = 'release';

      final result = await harness.run(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => harness.codePushClient.getAppPatchInstalls(
          appId: metricsTestAppId,
          granularity: 'week',
          groupBy: 'release',
        ),
      ).called(1);
    });

    test('queries a release when --release-version is given', () async {
      harness.args['release-version'] = '1.0.0+1';
      harness.args['group-by'] = 'patch';

      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getReleasePatchInstalls(
          appId: metricsTestAppId,
          releaseId: release.id,
          groupBy: 'patch',
        ),
      ).called(1);
    });

    test('rejects --group-by patch without --release-version', () async {
      harness.args['group-by'] = 'patch';

      await expectLater(
        harness.run(command.run),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            '--group-by patch requires --release-version.',
          ),
        ),
      );
    });

    test('rejects --group-by release with --release-version', () async {
      harness.args['group-by'] = 'release';
      harness.args['release-version'] = '1.0.0+1';

      await expectLater(
        harness.run(command.run),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            startsWith('--group-by release cannot be combined'),
          ),
        ),
      );
    });

    const previousLine =
        '  Previous window: 18 '
        '(2026-08-20T00:00:00Z to 2026-09-17T00:00:00Z)';

    test('prints totals, time series and breakdown', () async {
      await harness.run(command.run);

      expect(
        loggedLines(harness),
        equals([
          'Patch installs: 30',
          '  Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z',
          previousLine,
          'Time series (week):',
          '  2026-09-21T00:00:00Z  5',
          '  2026-09-28T00:00:00Z  25',
          'By release:',
          '  1.0.0+1  20',
          '  1.0.1+2  10',
        ]),
      );
    });

    test('names the release and omits absent sections', () async {
      harness.args['release-version'] = '1.0.0+1';
      when(
        () => harness.codePushClient.getReleasePatchInstalls(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenAnswer(
        (_) async => GetPatchMetricResponse(
          asOf: DateTime.utc(2026, 10, 15),
          granularity: null,
          current: PatchMetricCurrentWindow(count: 3, range: metricsTestRange),
        ),
      );

      await harness.run(command.run);

      expect(
        loggedLines(harness),
        equals([
          'Patch installs for release 1.0.0+1: 3',
          '  Window: 2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z',
        ]),
      );
    });
  });

  group(MetricsDownloadsCommand, () {
    late MetricsDownloadsCommand command;

    setUp(() {
      command = harness.createCommand(MetricsDownloadsCommand.new);
      when(
        () => harness.codePushClient.getAppPatchDownloads(
          appId: any(named: 'appId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenAnswer((_) async => response);
      when(
        () => harness.codePushClient.getReleasePatchDownloads(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenAnswer((_) async => response);
    });

    test('has the correct name and description', () {
      expect(command.name, equals('downloads'));
      expect(command.description, contains('downloaded'));
    });

    test('queries app-wide downloads', () async {
      harness.args['granularity'] = 'day';

      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getAppPatchDownloads(
          appId: metricsTestAppId,
          granularity: 'day',
        ),
      ).called(1);
      expect(loggedLines(harness).first, equals('Patch downloads: 30'));
    });

    test('queries a release when --release-version is given', () async {
      harness.args['release-version'] = '1.0.0+1';

      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getReleasePatchDownloads(
          appId: metricsTestAppId,
          releaseId: release.id,
        ),
      ).called(1);
    });
  });
}
