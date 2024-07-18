import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/list/list_releases_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group('$ListReleasesCommand', () {
    const appId = 'test-app-id';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersion = '3.22.0';
    const releaseVersion = '1.2.3+1';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final release = Release(
      id: 0,
      appId: appId,
      version: releaseVersion,
      flutterRevision: flutterRevision,
      flutterVersion: flutterVersion,
      displayName: '1.2.3+1',
      platformStatuses: {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;

    late ListReleasesCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(release);
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
      registerFallbackValue(ArgParser());
    });

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();

      command = ListReleasesCommand()..testArgResults = argResults;

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => argResults.wasParsed(any())).thenReturn(false);
    });

    test('has non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    test('default limit is 10', () {
      expect(ListReleasesCommand.defaultLimit, 10);
    });

    group('#run', () {
      void verifyReleaseLogs(
        Logger logger, {
        required int total,
        required int actual,
        int callCount = 1,
      }) {
        verify(() => logger.info('Found $total releases for $appId')).called(1);
        verify(() => logger.info('Latest Releases ($actual):')).called(1);
        verify(() => logger.info('')).called(1);
        verify(() => logger.info('1.2.3+1')).called(callCount);
        verify(() => logger.info('  Created: 01/01/2023 12:00 AM'))
            .called(callCount);
        verify(() => logger.info('  Last Updated: 01/01/2023 12:00 AM'))
            .called(callCount);
      }

      test('logs no releases found', () async {
        when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
        when(() => codePushClientWrapper.getReleases(appId: appId))
            .thenAnswer((_) => Future.value([]));

        await runWithOverrides(() => command.run());

        verify(() => logger.info('No releases found for $appId')).called(1);
        verifyNoMoreInteractions(logger);
      });

      test('logs releases', () async {
        when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
        when(() => codePushClientWrapper.getReleases(appId: appId))
            .thenAnswer((_) => Future.value([release]));

        await runWithOverrides(() => command.run());

        verifyReleaseLogs(logger, total: 1, actual: 1);

        verifyNoMoreInteractions(logger);
      });

      test('logs releases with limit', () async {
        when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
        when(() => codePushClientWrapper.getReleases(appId: appId))
            .thenAnswer((_) => Future.value([release, release, release]));

        when(() => argResults['limit']).thenReturn('1');

        await runWithOverrides(() => command.run());

        verifyReleaseLogs(logger, total: 3, actual: 1);

        verifyNoMoreInteractions(logger);
      });

      test('logs releases when limit is greater than releases length',
          () async {
        when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
        when(() => codePushClientWrapper.getReleases(appId: appId))
            .thenAnswer((_) => Future.value([release, release, release]));

        when(() => argResults['limit']).thenReturn('10');

        await runWithOverrides(() => command.run());

        verifyReleaseLogs(logger, total: 3, actual: 3, callCount: 3);

        verifyNoMoreInteractions(logger);
      });

      test('logs default limit when limit is <= 0', () async {
        when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
        when(() => codePushClientWrapper.getReleases(appId: appId))
            .thenAnswer((_) => Future.value([release, release, release]));

        when(() => argResults['limit']).thenReturn('0');

        await runWithOverrides(() => command.run());

        verifyReleaseLogs(logger, total: 3, actual: 3, callCount: 3);

        verifyNoMoreInteractions(logger);
      });
    });
  });
}
