import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'metrics_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  // The shared behavior lives in MetricsSubcommand; it is exercised here
  // through `metrics installs`, which uses every part of it (window options,
  // release lookup, the API call and both output modes).
  group(MetricsSubcommand, () {
    final harness = MetricsTestHarness();
    final response = GetPatchMetricResponse(
      asOf: DateTime.utc(2026, 10, 15),
      granularity: null,
      current: PatchMetricCurrentWindow(count: 12, range: metricsTestRange),
    );
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

    late MetricsInstallsCommand command;

    setUpAll(() {
      registerFallbackValue(DateTime(2026));
    });

    setUp(() {
      harness.setUp();
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
      when(
        () => harness.codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
    });

    test('returns the precondition failure exit code', () async {
      final exception = ShorebirdNotInitializedException();
      when(
        () => harness.shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenThrow(exception);

      final result = await harness.run(command.run);

      expect(result, equals(exception.exitCode.code));
      verifyNever(() => harness.codePushClientWrapper.codePushClient);
    });

    test('uses --app-id when given', () async {
      harness.args['app-id'] = 'explicit-app-id';

      await harness.run(command.run);

      verify(
        () => harness.codePushClient.getAppPatchInstalls(
          appId: 'explicit-app-id',
        ),
      ).called(1);
    });

    group('--start and --end', () {
      test('are passed as UTC instants', () async {
        harness.args['start'] = '2026-10-01';
        harness.args['end'] = '2026-10-02T12:30:00+02:00';

        await harness.run(command.run);

        verify(
          () => harness.codePushClient.getAppPatchInstalls(
            appId: metricsTestAppId,
            start: DateTime.utc(2026, 10),
            end: DateTime.utc(2026, 10, 2, 10, 30),
          ),
        ).called(1);
      });

      test('fail with a usage error when malformed', () async {
        harness.args['end'] = 'yesterday';

        await expectLater(
          harness.run(command.run),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('--end: "yesterday" is not an ISO 8601 date'),
            ),
          ),
        );
        verifyNever(() => harness.codePushClientWrapper.codePushClient);
      });
    });

    group('with --release-version', () {
      setUp(() {
        harness.args['release-version'] = '1.0.0+1';
      });

      test('looks up the release and queries it by id', () async {
        final result = await harness.run(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => harness.codePushClientWrapper.maybeGetRelease(
            appId: metricsTestAppId,
            releaseVersion: '1.0.0+1',
          ),
        ).called(1);
        verify(
          () => harness.codePushClient.getReleasePatchInstalls(
            appId: metricsTestAppId,
            releaseId: release.id,
          ),
        ).called(1);
      });

      group('when the release does not exist', () {
        setUp(() {
          when(
            () => harness.codePushClientWrapper.maybeGetRelease(
              appId: any(named: 'appId'),
              releaseVersion: any(named: 'releaseVersion'),
            ),
          ).thenAnswer((_) async => null);
        });

        test('reports a usage error', () async {
          final result = await harness.run(command.run);

          expect(result, equals(ExitCode.usage.code));
          verify(
            () => harness.logger.err('Release not found: "1.0.0+1".'),
          ).called(1);
        });

        test('reports a usage error envelope in --json mode', () async {
          final (:exitCode, :json) = await harness.runJson(command);

          expect(exitCode, equals(ExitCode.usage.code));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('usage_error'));
          expect(error['message'], equals('Release not found: "1.0.0+1".'));
        });
      });

      test('reports a failed release lookup in --json mode', () async {
        when(
          () => harness.codePushClientWrapper.maybeGetRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));

        final (:exitCode, :json) = await harness.runJson(command);

        expect(exitCode, equals(ExitCode.software.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], equals('fetch_failed'));
        expect(error['message'], equals('Failed to fetch releases.'));
      });
    });

    group('when the API returns an error', () {
      final exception = CodePushException.fromResponse(
        statusCode: HttpStatus.forbidden,
        response: const ErrorResponse(
          message: 'The account requires an upgraded plan.',
          details: 'More details.',
          code: 'shorebird_plan_insufficient_tier',
        ),
      );

      setUp(() {
        when(
          () => harness.codePushClient.getAppPatchInstalls(
            appId: any(named: 'appId'),
            start: any(named: 'start'),
            end: any(named: 'end'),
            granularity: any(named: 'granularity'),
            groupBy: any(named: 'groupBy'),
          ),
        ).thenThrow(exception);
      });

      test('logs the server message, details and code', () async {
        final result = await harness.run(command.run);

        expect(result, equals(ExitCode.software.code));
        verify(() => harness.progress.fail()).called(1);
        verify(
          () => harness.logger.err(
            'Failed to fetch patch installs. '
            'The account requires an upgraded plan.',
          ),
        ).called(1);
        verify(() => harness.logger.info('More details.')).called(1);
        verify(
          () => harness.logger.info(
            'Error code: shorebird_plan_insufficient_tier',
          ),
        ).called(1);
      });

      test('emits the server code in --json mode', () async {
        final (:exitCode, :json) = await harness.runJson(command);

        expect(exitCode, equals(ExitCode.software.code));
        expect(json['status'], equals('error'));
        expect(
          json['error'],
          equals({
            'code': 'fetch_failed',
            'message':
                'Failed to fetch patch installs. '
                'The account requires an upgraded plan.',
            'api_code': 'shorebird_plan_insufficient_tier',
            'details': 'More details.',
          }),
        );
      });
    });

    test('rethrows other errors after failing the progress', () async {
      when(
        () => harness.codePushClient.getAppPatchInstalls(
          appId: any(named: 'appId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          granularity: any(named: 'granularity'),
          groupBy: any(named: 'groupBy'),
        ),
      ).thenThrow(const FormatException('bad body'));

      await expectLater(
        harness.run(command.run),
        throwsA(isA<FormatException>()),
      );
      verify(() => harness.progress.fail()).called(1);
    });

    group('--json', () {
      test('emits the API response as data', () async {
        final (:exitCode, :json) = await harness.runJson(command);

        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], equals('success'));
        expect(json['data'], equals(response.toJson()));
        expect(
          (json['meta'] as Map<String, dynamic>)['command'],
          equals('installs'),
        );
      });

      test('does not use a progress spinner', () async {
        await harness.runJson(command);
        verifyNever(() => harness.logger.progress(any()));
      });
    });
  });

  group('formatting helpers', () {
    test('formatMetricsTime prints UTC to the second', () {
      expect(
        formatMetricsTime(DateTime.utc(2026, 10, 1, 2, 3, 4, 500)),
        equals('2026-10-01T02:03:04Z'),
      );
    });

    test('formatMetricsRange joins start and end', () {
      expect(
        formatMetricsRange(metricsTestRange),
        equals('2026-09-17T00:00:00Z to 2026-10-15T00:00:00Z'),
      );
    });

    test('formatPercent prints one decimal place', () {
      expect(formatPercent(0.4567), equals('45.7%'));
    });

    test('formatHour pads to two digits', () {
      expect(formatHour(3), equals('03:00'));
    });
  });
}
