import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();

  // OrgsGetCommand is the simplest OrganizationScopedCommand, so these tests
  // also cover how every such command picks its organization.
  group(OrgsGetCommand, () {
    const appId = 'test-app-id';
    final team = OrganizationMembership(
      organization: Organization(
        id: 42,
        name: 'Acme Corp',
        organizationType: OrganizationType.team,
        createdAt: DateTime.utc(2026, 1, 15),
        updatedAt: DateTime.utc(2026, 1, 16),
      ),
      role: Role.admin,
    );
    final personal = OrganizationMembership(
      organization: Organization(
        id: 7,
        name: 'user@example.com',
        organizationType: OrganizationType.personal,
        createdAt: DateTime.utc(2026, 1, 10),
        updatedAt: DateTime.utc(2026, 1, 11),
      ),
      role: Role.owner,
    );

    const position = AccountPosition(
      includedInstalls: 50000,
      installs: 12345,
      includedInstallsUsed: 12345,
      includedExhausted: false,
      overageInstalls: 0,
      installCeiling: 50000,
      remainingInstalls: 37655,
      atCeiling: false,
      nearingLimit: false,
      consumingOverage: false,
      accruedOverageAmount: null,
    );
    const usage = GetUsageResponse(
      apps: [],
      position: position,
      reportedOverage: null,
    );

    late ArgResults argResults;
    late AppMetadata app;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late OrgsGetCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => json),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      app = MockAppMetadata();
      codePushClientWrapper = MockCodePushClientWrapper();
      shorebirdEnv = MockShorebirdEnv();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(OrgsGetCommand.new)
        ..testArgResults = argResults;

      when(() => argResults['org-id']).thenReturn(null);
      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [personal, team]);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(null);
      when(() => app.organizationId).thenReturn(team.organization.id);
      when(
        () => codePushClientWrapper.maybeGetApp(appId: appId),
      ).thenAnswer((_) async => app);
      when(
        () => codePushClientWrapper.findAppOrganization(
          appId: appId,
          memberships: any(named: 'memberships'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => team);
      when(
        () => codePushClientWrapper.maybeGetOrganizationUsage(
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => usage);
    });

    test('requires the user to be signed in', () async {
      final exception = UserNotAuthorizedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).thenThrow(exception);
      expect(
        await runWithOverrides(command.run),
        equals(exception.exitCode.code),
      );
      verifyNever(() => codePushClientWrapper.getOrganizationMemberships());
    });

    group('with --org-id', () {
      test('shows the organization it names', () async {
        when(() => argResults['org-id']).thenReturn('42');
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.success.code),
        );
        final lines = verify(
          () => logger.info(captureAny()),
        ).captured.cast<String>();
        expect(lines, [
          contains('Acme Corp'),
          'id: 42',
          'type: team',
          'your role: admin',
          'created: 2026-01-15',
          'patch installs: 12,345 of 50,000 included',
        ]);
      });

      test('rejects an id that is not a number', () async {
        when(() => argResults['org-id']).thenReturn('acme');
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.usage.code),
        );
        verify(
          () => logger.err('"acme" is not a valid organization id.'),
        ).called(1);
      });

      test('rejects an organization the user is not in', () async {
        when(() => argResults['org-id']).thenReturn('99');
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.usage.code),
        );
        verify(
          () => logger.err('You are not a member of organization 99.'),
        ).called(1);
        verify(
          () => logger.info(
            'Your organizations: user@example.com (id: 7), '
            'Acme Corp (id: 42).',
          ),
        ).called(1);
      });
    });

    group('with a positional id', () {
      test('shows the organization it names', () async {
        when(() => argResults.rest).thenReturn(['42']);
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.success.code),
        );
        verify(() => logger.info('id: 42')).called(1);
      });

      test('rejects an id given twice', () async {
        when(() => argResults.rest).thenReturn(['42']);
        when(() => argResults['org-id']).thenReturn('7');
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.usage.code),
        );
        verify(
          () => logger.err(
            'Pass one organization id, not "7" and "42": '
            'shorebird orgs get <org-id>.',
          ),
        ).called(1);
        verifyNever(() => codePushClientWrapper.getOrganizationMemberships());
      });
    });

    group('without --org-id', () {
      test("uses the organization of shorebird.yaml's app", () async {
        when(
          () => shorebirdEnv.getShorebirdYaml(),
        ).thenReturn(const ShorebirdYaml(appId: appId));
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.success.code),
        );
        verify(
          () => codePushClientWrapper.findAppOrganization(
            appId: appId,
            memberships: [personal, team],
            organizationId: 42,
          ),
        ).called(1);
        verify(() => logger.info('id: 42')).called(1);
        verify(
          () => logger.info(
            'Using organization "Acme Corp" (id: 42), which owns the app in '
            'shorebird.yaml. Pass --org-id to choose another.',
          ),
        ).called(1);
      });

      test('reports a failure to look up the app', () async {
        when(
          () => shorebirdEnv.getShorebirdYaml(),
        ).thenReturn(const ShorebirdYaml(appId: appId));
        when(
          () => codePushClientWrapper.maybeGetApp(appId: appId),
        ).thenThrow(ProcessExit(ExitCode.software.code));
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        expect(
          (json['error'] as Map)['message'],
          'Failed to find the organization of app "$appId".',
        );
      });

      test(
        "won't guess when the app isn't in the user's organizations",
        () async {
          when(
            () => shorebirdEnv.getShorebirdYaml(),
          ).thenReturn(const ShorebirdYaml(appId: appId));
          when(
            () => codePushClientWrapper.findAppOrganization(
              appId: appId,
              memberships: any(named: 'memberships'),
              organizationId: any(named: 'organizationId'),
            ),
          ).thenAnswer((_) async => null);
          when(
            () => codePushClientWrapper.getOrganizationMemberships(),
          ).thenAnswer((_) async => [personal]);
          expect(
            await runWithOverrides(command.run),
            equals(ExitCode.usage.code),
          );
          verify(
            () => logger.err(
              'App "$appId" in shorebird.yaml is not in any of your '
              'organizations. Pass --org-id to choose one.',
            ),
          ).called(1);
        },
      );

      test("won't guess when the user can't see the app", () async {
        when(
          () => shorebirdEnv.getShorebirdYaml(),
        ).thenReturn(const ShorebirdYaml(appId: appId));
        when(
          () => codePushClientWrapper.maybeGetApp(appId: appId),
        ).thenAnswer((_) async => null);
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.usage.code),
        );
        verifyNever(
          () => codePushClientWrapper.findAppOrganization(
            appId: any(named: 'appId'),
            memberships: any(named: 'memberships'),
            organizationId: any(named: 'organizationId'),
          ),
        );
      });

      test('uses the only organization', () async {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
        ).thenAnswer((_) async => [team]);
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.success.code),
        );
        verify(() => logger.info('id: 42')).called(1);
        verify(
          () => logger.info(
            'Using organization "Acme Corp" (id: 42), your only '
            'organization. Pass --org-id to choose another.',
          ),
        ).called(1);
      });

      test('asks for --org-id and lists the choices', () async {
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.usage.code),
        );
        verify(
          () => logger.err('Pass --org-id to choose an organization.'),
        ).called(1);
        verify(
          () => logger.info(
            'Your organizations: user@example.com (id: 7), '
            'Acme Corp (id: 42).',
          ),
        ).called(1);
      });
    });

    test('reports a failure to fetch organizations', () async {
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.software.code));
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch organizations.',
      );
    });

    test('--json emits the organization and your role', () async {
      when(() => argResults['org-id']).thenReturn('42');
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.success.code));
      expect(json['data'], {
        'id': 42,
        'name': 'Acme Corp',
        'type': 'team',
        'role': 'admin',
        'created_at': '2026-01-15T00:00:00.000Z',
        'updated_at': '2026-01-16T00:00:00.000Z',
        'usage': position.toJson(),
      });
    });

    group('when the role may not see usage', () {
      setUp(() {
        when(() => argResults['org-id']).thenReturn('42');
        when(
          () => codePushClientWrapper.maybeGetOrganizationUsage(
            organizationId: 42,
          ),
        ).thenAnswer((_) async => null);
      });

      test('leaves the usage line out', () async {
        expect(
          await runWithOverrides(command.run),
          equals(ExitCode.success.code),
        );
        final lines = verify(
          () => logger.info(captureAny()),
        ).captured.cast<String>();
        expect(lines.last, 'created: 2026-01-15');
      });

      test('--json gives null usage', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect((json['data'] as Map)['usage'], isNull);
      });
    });

    test('fails when usage fails any other way', () async {
      when(() => argResults['org-id']).thenReturn('42');
      when(
        () => codePushClientWrapper.maybeGetOrganizationUsage(
          organizationId: 42,
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.software.code));
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch usage for organization 42.',
      );
    });
  });
}
