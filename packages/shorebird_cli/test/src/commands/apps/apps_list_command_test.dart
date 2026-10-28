import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/apps/apps_list_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';
import '../enterprises/enterprise_fixtures.dart';
import '../enterprises/enterprise_test_harness.dart';

void main() {
  useTempWorkingDirectory();
  group(AppsListCommand, () {
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
    late AppsListCommand command;

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
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(AppsListCommand.new)
        ..testArgResults = argResults;

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

    test('name and description are correct', () {
      expect(command.name, 'list');
      expect(
        command.description,
        startsWith('Lists the apps you have access to.'),
      );
      expect(command.description, contains('shorebird apps list --json'));
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

      test('in --json mode, emits JSON error envelope', () async {
        final (:exitCode, :json) = await captureJson(
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
        );
        expect(exitCode, equals(ExitCode.software.code));
        expect(json['status'], 'error');
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
        final (:exitCode, :json) = await captureJson(
          () => runJsonMode(command.run),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], 'success');
        final data = json['data'] as Map<String, dynamic>;
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
        final json = (await captureJson(
          () => runJsonMode(command.run),
        )).json;
        final apps =
            ((json['data'] as Map<String, dynamic>)['apps'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
        for (final app in apps) {
          expect(app.containsKey('created_at'), isFalse);
          expect(app.containsKey('updated_at'), isFalse);
        }
      });

      test('emits empty array when there are no apps', () async {
        when(() => codePushClientWrapper.getApps()).thenAnswer((_) async => []);
        final (:exitCode, :json) = await captureJson(
          () => runJsonMode(command.run),
        );
        expect(exitCode, equals(ExitCode.success.code));
        final data = json['data'] as Map<String, dynamic>;
        expect(data['apps'], isEmpty);
      });
    });
  });

  group('AppsListCommand --enterprise-id', () {
    late EnterpriseHarness h;
    late AppsListCommand command;

    setUp(() {
      h = EnterpriseHarness();
      when(
        () => h.codePushClientWrapper.getEnterpriseApps(enterpriseId: 7),
      ).thenAnswer((_) async => [EnterpriseFixtures.app]);
      command = h.run(AppsListCommand.new)..testArgResults = h.argResults;
    });

    test('lists every app with its organization', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        allOf(
          startsWith('app-1  '),
          contains('Acme App'),
          endsWith('42  Mobile'),
        ),
      ]);
      verifyNever(h.codePushClientWrapper.getApps);
    });

    test('says when the enterprise has none', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseApps(enterpriseId: 7),
      ).thenAnswer((_) async => []);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(() => h.logger.info('"Acme" has no apps.')).called(1);
    });

    test("--json names each app's organization", () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'enterprise_id': 7,
        'apps': [
          {
            'app_id': 'app-1',
            'display_name': 'Acme App',
            'organization_id': 42,
            'organization_name': 'Mobile',
          },
        ],
      });
    });

    test('rejects an id that is not a number', () async {
      when(() => h.argResults['enterprise-id']).thenReturn('acme');
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(
        () => h.codePushClientWrapper.getEnterpriseApps(
          enterpriseId: any(named: 'enterpriseId'),
        ),
      );
    });

    test('reports a failed fetch', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseApps(enterpriseId: 7),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch the apps of enterprise 7.',
      );
    });
  });
}
