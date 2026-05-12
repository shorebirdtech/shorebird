import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/apps_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  group(AppsCommand, () {
    final appWithReleases = AppMetadata(
      appId: '01H000000000000000000ABCDE',
      displayName: 'Acme Mobile',
      latestReleaseVersion: '1.2.3',
      latestPatchNumber: 4,
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 16),
    );
    final appWithoutReleases = AppMetadata(
      appId: '01J000000000000000000ABCDE',
      displayName: 'Acme Internal',
      createdAt: DateTime(2026, 2),
      updatedAt: DateTime(2026, 2, 2),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late Progress progress;
    late AppsCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => false),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(AppsCommand.new)..testArgResults = argResults;

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getApps(),
      ).thenAnswer((_) async => [appWithReleases, appWithoutReleases]);
    });

    test('has correct description', () {
      expect(
        command.description,
        startsWith('List the apps you have access to.'),
      );
    });

    group('when validation fails', () {
      final exception = UserNotAuthorizedException();

      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          ),
        ).thenThrow(exception);
      });

      test('returns the precondition failure exit code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(exception.exitCode.code));
      });
    });

    test('requires user to be authenticated', () async {
      await runWithOverrides(command.run);
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    group('human-readable output', () {
      test('prints one line per app', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final lines = verify(
          () => logger.info(captureAny()),
        ).captured.cast<String>();
        expect(lines, hasLength(2));
        expect(
          lines[0],
          allOf(
            contains('Acme Mobile'),
            contains('1.2.3'),
            contains('4'),
            contains(appWithReleases.appId),
          ),
        );
        expect(
          lines[1],
          allOf(
            contains('Acme Internal'),
            contains('-'),
            contains(appWithoutReleases.appId),
          ),
        );
      });

      group('when there are no apps', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getApps(),
          ).thenAnswer((_) async => []);
        });

        test('prints an empty-state message', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(() => logger.info('No apps found.')).called(1);
        });
      });
    });

    group('when API fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getApps(),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('in human-readable mode, rethrows ProcessExit', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ProcessExit>()),
        );
      });

      test('in --json mode, emits JSON error envelope', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runScoped(
            command.run,
            values: {
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              isJsonModeRef.overrideWith(() => true),
              loggerRef.overrideWith(() => logger),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
          captured: captured,
        );
        expect(result, equals(ExitCode.software.code));
        expect(captured, hasLength(1));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'error');
      });
    });

    group('--json', () {
      R runJsonMode<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            isJsonModeRef.overrideWith(() => true),
            loggerRef.overrideWith(() => logger),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        );
      }

      test('emits JSON success with flat app fields', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runJsonMode(command.run),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        expect(captured, hasLength(1));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'success');
        final data = decoded['data'] as Map<String, dynamic>;
        final apps = data['apps'] as List<dynamic>;
        expect(apps, hasLength(2));
        final firstApp = apps.first as Map<String, dynamic>;
        expect(firstApp['app_id'], appWithReleases.appId);
        expect(firstApp['display_name'], 'Acme Mobile');
        expect(firstApp['latest_release_version'], '1.2.3');
        expect(firstApp['latest_patch_number'], 4);
        final secondApp = apps[1] as Map<String, dynamic>;
        expect(secondApp['latest_release_version'], isNull);
        expect(secondApp['latest_patch_number'], isNull);
      });

      test('does not leak timestamps or protocol-internal fields', () async {
        final captured = <String>[];
        await captureStdout(
          () => runJsonMode(command.run),
          captured: captured,
        );
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final apps =
            ((decoded['data'] as Map<String, dynamic>)['apps'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
        for (final app in apps) {
          expect(app.containsKey('created_at'), isFalse);
          expect(app.containsKey('updated_at'), isFalse);
        }
      });

      test('emits empty array when there are no apps', () async {
        when(() => codePushClientWrapper.getApps()).thenAnswer((_) async => []);
        final captured = <String>[];
        final result = await captureStdout(
          () => runJsonMode(command.run),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
        expect(data['apps'], isEmpty);
      });
    });
  });
}
