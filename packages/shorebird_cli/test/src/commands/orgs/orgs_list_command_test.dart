import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs_list_command.dart';
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
  group(OrgsListCommand, () {
    final teamMembership = OrganizationMembership(
      organization: Organization(
        id: 1,
        name: 'Acme Corp',
        organizationType: OrganizationType.team,
        createdAt: DateTime(2026, 1, 15),
        updatedAt: DateTime(2026, 1, 16),
      ),
      role: Role.admin,
    );
    final personalMembership = OrganizationMembership(
      organization: Organization(
        id: 2,
        name: 'user@example.com',
        organizationType: OrganizationType.personal,
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 11),
      ),
      role: Role.owner,
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late OrgsListCommand command;

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
      command = runWithOverrides(OrgsListCommand.new)
        ..testArgResults = argResults;

      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [teamMembership, personalMembership]);
    });

    test('has correct description', () {
      expect(
        command.description,
        startsWith('List the organizations you can access.'),
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
      test('prints one line per organization', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final lines = verify(
          () => logger.info(captureAny()),
        ).captured.cast<String>();
        expect(lines, hasLength(2));
        expect(lines[0], allOf(contains('Acme Corp'), contains('admin')));
        expect(
          lines[1],
          allOf(contains('user@example.com'), contains('owner')),
        );
      });

      group('when there are no organizations', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getOrganizationMemberships(),
          ).thenAnswer((_) async => []);
        });

        test('prints an empty-state message', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(() => logger.info('No organizations found.')).called(1);
        });
      });
    });

    group('when API fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
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

      test('emits JSON success with flat organization fields', () async {
        final (:exitCode, :json) = await captureJson(
          () => runJsonMode(command.run),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], 'success');
        final data = json['data'] as Map<String, dynamic>;
        final orgs = data['organizations'] as List<dynamic>;
        expect(orgs, hasLength(2));
        final firstOrg = orgs.first as Map<String, dynamic>;
        expect(firstOrg['id'], 1);
        expect(firstOrg['name'], 'Acme Corp');
        expect(firstOrg['type'], 'team');
        expect(firstOrg['role'], 'admin');
      });

      test('does not leak timestamps or protocol-internal fields', () async {
        final json = (await captureJson(
          () => runJsonMode(command.run),
        )).json;
        final orgs =
            ((json['data'] as Map<String, dynamic>)['organizations']
                    as List<dynamic>)
                .cast<Map<String, dynamic>>();
        for (final org in orgs) {
          expect(org.containsKey('created_at'), isFalse);
          expect(org.containsKey('updated_at'), isFalse);
          expect(org.containsKey('organization_type'), isFalse);
          expect(org.containsKey('organization'), isFalse);
        }
      });

      test('emits empty array when there are no organizations', () async {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
        ).thenAnswer((_) async => []);
        final (:exitCode, :json) = await captureJson(
          () => runJsonMode(command.run),
        );
        expect(exitCode, equals(ExitCode.success.code));
        final data = json['data'] as Map<String, dynamic>;
        expect(data['organizations'], isEmpty);
      });
    });
  });

  group('OrgsListCommand --enterprise', () {
    late EnterpriseHarness h;
    late OrgsListCommand command;

    setUp(() {
      h = EnterpriseHarness();
      when(
        () => h.codePushClientWrapper.getEnterpriseOrganizations(
          enterpriseId: 7,
        ),
      ).thenAnswer((_) async => [EnterpriseFixtures.mobile]);
      command = h.run(OrgsListCommand.new)..testArgResults = h.argResults;
    });

    test('lists every organization in the enterprise', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        allOf(
          startsWith('42  '),
          contains('Mobile'),
          endsWith('12 members  1 app'),
        ),
      ]);
      verifyNever(h.codePushClientWrapper.getOrganizationMemberships);
    });

    test('says when the enterprise has none', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseOrganizations(
          enterpriseId: 7,
        ),
      ).thenAnswer((_) async => []);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(() => h.logger.info('"Acme" has no organizations.')).called(1);
    });

    test('--json lists counts', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'enterprise_id': 7,
        'organizations': [
          {'id': 42, 'name': 'Mobile', 'member_count': 12, 'app_count': 1},
        ],
      });
    });

    test('says when you are in no enterprise', () async {
      when(h.codePushClientWrapper.getEnterprises).thenAnswer((_) async => []);
      expect(await h.run(command.run), ExitCode.noPerm.code);
      verify(
        () => h.logger.err("You aren't a member of an enterprise."),
      ).called(1);
    });

    test('reports a failed fetch', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseOrganizations(
          enterpriseId: 7,
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch the organizations of "Acme".',
      );
    });
  });
}
