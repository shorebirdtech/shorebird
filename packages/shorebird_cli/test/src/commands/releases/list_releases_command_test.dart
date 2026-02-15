import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/releases/releases.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(ListReleasesCommand, () {
    const appId = 'test-app-id';

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdYaml shorebirdYaml;
    late ListReleasesCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdYaml = MockShorebirdYaml();

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdYaml.appId).thenReturn(appId);

      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults['plain']).thenReturn(false);
      when(() => argResults['platform']).thenReturn(null);
      when(() => argResults['flavor']).thenReturn(null);
      when(() => argResults.rest).thenReturn([]);

      command = ListReleasesCommand()..testArgResults = argResults;
    });

    test('has correct name and description', () {
      expect(command.name, equals('list'));
      expect(command.description, isNotEmpty);
    });

    test('exits with error code when precondition fails', () async {
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenThrow(UserNotAuthorizedException());

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.noUser.code));
    });

    test('prints message when no releases found', () async {
      when(
        () => codePushClientWrapper.getReleases(appId: appId),
      ).thenAnswer((_) async => []);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('No releases found')).called(1);
    });

    test('lists releases sorted by date descending', () async {
      final olderRelease = Release(
        id: 1,
        appId: appId,
        version: '1.0.0',
        flutterRevision: 'abc',
        flutterVersion: '3.16.0',
        displayName: null,
        platformStatuses: {
          ReleasePlatform.android: ReleaseStatus.active,
        },
        createdAt: DateTime(2024, 1, 15),
        updatedAt: DateTime(2024, 1, 15),
      );

      final newerRelease = Release(
        id: 2,
        appId: appId,
        version: '1.1.0',
        flutterRevision: 'def',
        flutterVersion: '3.16.3',
        displayName: null,
        platformStatuses: {
          ReleasePlatform.android: ReleaseStatus.active,
          ReleasePlatform.ios: ReleaseStatus.active,
        },
        createdAt: DateTime(2024, 2, 20),
        updatedAt: DateTime(2024, 2, 20),
      );

      when(
        () => codePushClientWrapper.getReleases(appId: appId),
      ).thenAnswer((_) async => [olderRelease, newerRelease]);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));

      final infoLogs = verify(() => logger.info(captureAny())).captured;
      final logStrings = infoLogs.cast<String>();

      // Newer release should appear before older
      final newerIndex = logStrings.indexWhere((s) => s.contains('1.1.0'));
      final olderIndex = logStrings.indexWhere((s) => s.contains('1.0.0'));
      expect(newerIndex, lessThan(olderIndex));

      expect(logStrings, contains('2 release(s) total'));
    });

    test('displays platform statuses', () async {
      final release = Release(
        id: 1,
        appId: appId,
        version: '1.0.0',
        flutterRevision: 'abc',
        flutterVersion: '3.16.0',
        displayName: null,
        platformStatuses: {
          ReleasePlatform.android: ReleaseStatus.active,
          ReleasePlatform.ios: ReleaseStatus.draft,
        },
        createdAt: DateTime(2024, 3, 10),
        updatedAt: DateTime(2024, 3, 10),
      );

      when(
        () => codePushClientWrapper.getReleases(appId: appId),
      ).thenAnswer((_) async => [release]);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));

      final infoLogs = verify(() => logger.info(captureAny())).captured;
      final logStrings = infoLogs.cast<String>();
      final releaseLine = logStrings.firstWhere((s) => s.contains('1.0.0'));

      expect(releaseLine, contains('Android: active'));
      expect(releaseLine, contains('iOS: draft'));
    });

    group('--platform', () {
      test('filters releases to the specified platform', () async {
        when(() => argResults['platform']).thenReturn('android');

        final androidRelease = Release(
          id: 1,
          appId: appId,
          version: '1.0.0',
          flutterRevision: 'abc',
          flutterVersion: '3.16.0',
          displayName: null,
          platformStatuses: {
            ReleasePlatform.android: ReleaseStatus.active,
          },
          createdAt: DateTime(2024, 1, 15),
          updatedAt: DateTime(2024, 1, 15),
        );

        final iosRelease = Release(
          id: 2,
          appId: appId,
          version: '2.0.0',
          flutterRevision: 'def',
          flutterVersion: '3.16.3',
          displayName: null,
          platformStatuses: {
            ReleasePlatform.ios: ReleaseStatus.active,
          },
          createdAt: DateTime(2024, 2, 20),
          updatedAt: DateTime(2024, 2, 20),
        );

        when(
          () => codePushClientWrapper.getReleases(appId: appId),
        ).thenAnswer((_) async => [androidRelease, iosRelease]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));

        final infoLogs = verify(() => logger.info(captureAny())).captured;
        final logStrings = infoLogs.cast<String>();

        expect(logStrings.any((s) => s.contains('1.0.0')), isTrue);
        expect(logStrings.any((s) => s.contains('2.0.0')), isFalse);
        expect(logStrings, contains('1 release(s) total'));
      });

      test('shows no releases when platform has none', () async {
        when(() => argResults['platform']).thenReturn('ios');

        final androidRelease = Release(
          id: 1,
          appId: appId,
          version: '1.0.0',
          flutterRevision: 'abc',
          flutterVersion: '3.16.0',
          displayName: null,
          platformStatuses: {
            ReleasePlatform.android: ReleaseStatus.active,
          },
          createdAt: DateTime(2024, 1, 15),
          updatedAt: DateTime(2024, 1, 15),
        );

        when(
          () => codePushClientWrapper.getReleases(appId: appId),
        ).thenAnswer((_) async => [androidRelease]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(() => logger.info('No releases found')).called(1);
      });
    });

    group('--flavor', () {
      test('uses flavor app ID when specified', () async {
        const flavorAppId = 'flavor-app-id';
        when(() => argResults.wasParsed('flavor')).thenReturn(true);
        when(() => argResults['flavor']).thenReturn('ci');
        when(() => shorebirdYaml.flavors).thenReturn({'ci': flavorAppId});

        final release = Release(
          id: 1,
          appId: flavorAppId,
          version: '2.0.0',
          flutterRevision: 'abc',
          flutterVersion: '3.16.0',
          displayName: null,
          platformStatuses: {
            ReleasePlatform.ios: ReleaseStatus.active,
          },
          createdAt: DateTime(2024, 3, 10),
          updatedAt: DateTime(2024, 3, 10),
        );

        when(
          () => codePushClientWrapper.getReleases(appId: flavorAppId),
        ).thenAnswer((_) async => [release]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.getReleases(appId: flavorAppId),
        ).called(1);
      });
    });

    group('--plain', () {
      setUp(() {
        when(() => argResults['plain']).thenReturn(true);
      });

      test('outputs only version strings', () async {
        final release = Release(
          id: 1,
          appId: appId,
          version: '1.0.0',
          flutterRevision: 'abc',
          flutterVersion: '3.16.0',
          displayName: null,
          platformStatuses: {
            ReleasePlatform.android: ReleaseStatus.active,
          },
          createdAt: DateTime(2024, 3, 10),
          updatedAt: DateTime(2024, 3, 10),
        );

        when(
          () => codePushClientWrapper.getReleases(appId: appId),
        ).thenAnswer((_) async => [release]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));

        final infoLogs = verify(() => logger.info(captureAny())).captured;
        final logStrings = infoLogs.cast<String>();

        expect(logStrings, equals(['1.0.0']));
      });

      test('outputs nothing when no releases found', () async {
        when(
          () => codePushClientWrapper.getReleases(appId: appId),
        ).thenAnswer((_) async => []);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verifyNever(() => logger.info(any()));
      });
    });
  });
}
