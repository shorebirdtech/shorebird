import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/apps/apps.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AppsArchiveCommand, () {
    const appId = 'app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late AppsArchiveCommand command;

    R runWithOverrides<R>(
      R Function() body, {
      bool jsonMode = false,
    }) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
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

      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['app-id']).thenReturn(null);
      when(() => argResults['flavor']).thenReturn(null);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);

      when(
        () => codePushClientWrapper.archiveApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(AppsArchiveCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'archive');
      expect(command.description, startsWith('Archives an app.'));
      expect(command.description, contains('--json'));
    });

    test('archives the app from shorebird.yaml', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => codePushClientWrapper.archiveApp(appId: appId)).called(1);
      verify(() => logger.success('Archived app "$appId".')).called(1);
    });

    group('when --app-id is passed', () {
      const explicitAppId = 'other-app-id';

      setUp(() => when(() => argResults['app-id']).thenReturn(explicitAppId));

      test('archives that app without reading shorebird.yaml', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.archiveApp(appId: explicitAppId),
        ).called(1);
        verifyNever(() => shorebirdEnv.getShorebirdYaml());
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
          ),
        ).called(1);
      });
    });

    group('when preconditions fail', () {
      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(UserNotAuthorizedException());
      });

      test('returns the precondition exit code and does not write', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.noUser.code));
        verifyNever(
          () => codePushClientWrapper.archiveApp(appId: any(named: 'appId')),
        );
      });
    });

    group('when the request fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.archiveApp(appId: any(named: 'appId')),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('lets the logged failure stand and does not succeed', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ProcessExit>()),
        );
        verifyNever(() => logger.success(any()));
      });

      test('emits a JSON error envelope in --json mode', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        expect(
          (json['error'] as Map<String, dynamic>)['code'],
          'software_error',
        );
      });
    });

    group('--json', () {
      test('emits app_id and archived', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], 'success');
        expect(json['data'], equals({'app_id': appId, 'archived': true}));
        verifyNever(() => logger.success(any()));
      });
    });
  });
}
