import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:shorebird_cli/src/commands/usage_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';
import 'enterprises/enterprise_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(UsageCommand, () {
    final membership = OrganizationMembership(
      organization: Organization(
        id: 42,
        name: 'Acme Corp',
        organizationType: OrganizationType.team,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      role: Role.admin,
    );
    AccountPosition position({
      int overageInstalls = 0,
      int? remainingInstalls = 37655,
      bool atCeiling = false,
      bool nearingLimit = false,
      String? accruedOverageAmount,
    }) => AccountPosition(
      includedInstalls: 50000,
      installs: 12345,
      includedInstallsUsed: 12345,
      includedExhausted: false,
      overageInstalls: overageInstalls,
      installCeiling: remainingInstalls == null ? null : 50000,
      remainingInstalls: remainingInstalls,
      atCeiling: atCeiling,
      nearingLimit: nearingLimit,
      consumingOverage: false,
      accruedOverageAmount: accruedOverageAmount,
    );
    GetUsageResponse usage({
      AccountPosition? accountPosition,
      List<AppUsage> apps = const [
        AppUsage(id: 'app-1', name: 'Acme Mobile', patchInstallCount: 12345),
      ],
    }) => GetUsageResponse(
      apps: apps,
      position: accountPosition ?? position(),
      reportedOverage: null,
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late UsageCommand command;

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

    void returnUsage(GetUsageResponse response) {
      when(
        () => codePushClientWrapper.getOrganizationUsage(organizationId: 42),
      ).thenAnswer((_) async => response);
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.hostedEnvironment).thenReturn(null);
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(UsageCommand.new)..testArgResults = argResults;

      when(() => argResults['org-id']).thenReturn('42');
      when(() => argResults.rest).thenReturn([]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getOrganizationMemberships(),
      ).thenAnswer((_) async => [membership]);
      returnUsage(usage());
    });

    test('is visible at the top level, and hidden under orgs and account', () {
      expect(command.hidden, isFalse);
      final orgsUsage = OrgsCommand().subcommands['usage'];
      expect(orgsUsage, isA<OrgsUsageCommand>());
      expect(orgsUsage!.hidden, isTrue);
      final accountUsage = AccountCommand().subcommands['usage'];
      expect(accountUsage, isA<AccountUsageCommand>());
      expect(accountUsage!.hidden, isTrue);
    });

    test('takes the org id as an argument', () async {
      when(() => argResults['org-id']).thenReturn(null);
      when(() => argResults.rest).thenReturn(['42']);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => codePushClientWrapper.getOrganizationUsage(organizationId: 42),
      ).called(1);
    });

    test('shows installs against the plan and each app', () async {
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      final lines = verify(
        () => logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        'Patch installs: 12,345 of 50,000 included',
        'Installs left before patches stop: 37,655',
        'Apps (id  name  installs):',
        allOf(contains('app-1'), contains('Acme Mobile'), endsWith('12,345')),
      ]);
      verifyNever(() => logger.warn(any()));
    });

    test('shows overage, and no ceiling when there is none', () async {
      returnUsage(
        usage(
          accountPosition: position(
            overageInstalls: 200,
            remainingInstalls: null,
            accruedOverageAmount: '1234.5',
          ),
          apps: const [],
        ),
      );
      await runWithOverrides(command.run);
      final lines = verify(
        () => logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        'Patch installs: 12,345 of 50,000 included',
        "Billed as overage: 200 (12.35 so far, in your plan's currency)",
      ]);
    });

    test(
      'says to upgrade when patches stop on a plan without overage',
      () async {
        returnUsage(
          usage(
            accountPosition: position(remainingInstalls: 0, atCeiling: true),
          ),
        );
        await runWithOverrides(command.run);
        verify(
          () => logger.warn(
            'Patches have stopped: the account reached its install limit. '
            'Upgrade your plan at https://console.shorebird.dev.',
          ),
        ).called(1);
      },
    );

    test('says to raise the overage limit on a plan with overage', () async {
      returnUsage(
        usage(
          accountPosition: position(
            remainingInstalls: 0,
            atCeiling: true,
            accruedOverageAmount: '0',
          ),
        ),
      );
      await runWithOverrides(command.run);
      verify(
        () => logger.warn(
          'Patches have stopped: the account reached its install limit. '
          'Raise your overage limit at https://console.shorebird.dev.',
        ),
      ).called(1);
    });

    test('links the console of the environment the CLI talks to', () async {
      when(() => shorebirdEnv.hostedEnvironment).thenReturn(devEnvironment);
      returnUsage(
        usage(accountPosition: position(remainingInstalls: 0, atCeiling: true)),
      );
      await runWithOverrides(command.run);
      final warning =
          verify(() => logger.warn(captureAny())).captured.single as String;
      expect(warning, endsWith('Upgrade your plan at $devConsoleUrl.'));
    });

    test('warns, with a next step, when nearing the limit', () async {
      returnUsage(usage(accountPosition: position(nearingLimit: true)));
      await runWithOverrides(command.run);
      verify(
        () => logger.warn(
          'The account is nearing its install limit, after which patches '
          'stop. Upgrade your plan at https://console.shorebird.dev.',
        ),
      ).called(1);
    });

    test('stops when the organization cannot be picked', () async {
      when(() => argResults['org-id']).thenReturn('99');
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
      verifyNever(
        () => codePushClientWrapper.getOrganizationUsage(
          organizationId: any(named: 'organizationId'),
        ),
      );
    });

    test('reports a failed request', () async {
      when(
        () => codePushClientWrapper.getOrganizationUsage(organizationId: 42),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch usage for organization 42.',
      );
    });

    test('--json emits the usage as the API returns it', () async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {'organization_id': 42, ...usage().toJson()});
    });
  });

  group('UsageCommand --enterprise-id', () {
    late EnterpriseHarness h;
    late UsageCommand command;

    final billing = EnterpriseBilling.fromJson(const {
      'has_billing_account': true,
      'plan': {
        'name': 'Enterprise',
        'level': 'enterprise',
        'billing_interval': 'month',
        'billing_interval_count': 1,
        'current_period_start': '2026-10-01T00:00:00.000Z',
        'current_period_end': '2026-11-01T00:00:00.000Z',
        'cancel_at_period_end': false,
        'currency': 'usd',
      },
      'position': {
        'included_installs': 1000000,
        'installs': 950000,
        'included_installs_used': 950000,
        'included_exhausted': false,
        'overage_installs': 0,
        'install_ceiling': 1000000,
        'remaining_installs': 50000,
        'at_ceiling': false,
        'nearing_limit': true,
        'consuming_overage': false,
        'accrued_overage_amount': null,
      },
    });
    final mobile = EnterpriseBillingOrganization.fromJson(const {
      'id': 42,
      'name': 'Mobile',
      'app_count': 1,
      'patch_installs': 950000,
    });

    setUp(() {
      h = EnterpriseHarness();
      when(
        () => h.codePushClientWrapper.getEnterpriseBilling(enterpriseId: 7),
      ).thenAnswer((_) async => billing);
      when(
        () => h.codePushClientWrapper.getEnterpriseBillingOrganizations(
          enterpriseId: 7,
        ),
      ).thenAnswer((_) async => [mobile]);
      command = h.run(UsageCommand.new)..testArgResults = h.argResults;
    });

    test('shows the plan, then each organization', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        'Plan: Enterprise, this period 2026-10-01 to 2026-11-01',
        'Patch installs: 950,000 of 1,000,000 included',
        'Installs left before patches stop: 50,000',
        'Organizations (id  name  installs):',
        allOf(startsWith('  42  '), contains('Mobile'), endsWith('950,000')),
      ]);
      // A contract sets the limit, so there's no setting to point at.
      verify(
        () => h.logger.warn(
          'The account is nearing its install limit, after which patches '
          'stop. Your contract sets the limit; ask your Shorebird contact to '
          'raise it.',
        ),
      ).called(1);
    });

    test('says when the enterprise has no billing account', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseBilling(enterpriseId: 7),
      ).thenAnswer(
        (_) async => EnterpriseBilling.fromJson(const {
          'has_billing_account': false,
          'plan': null,
          'position': null,
        }),
      );
      when(
        () => h.codePushClientWrapper.getEnterpriseBillingOrganizations(
          enterpriseId: 7,
        ),
      ).thenAnswer((_) async => []);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(() => h.logger.info('"Acme" has no billing account.')).called(1);
    });

    test('--json has the plan, position and organizations', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      final data = json['data'] as Map<String, dynamic>;
      expect(data['enterprise_id'], 7);
      expect((data['plan'] as Map)['name'], 'Enterprise');
      expect(data['organizations'], [
        {'id': 42, 'name': 'Mobile', 'app_count': 1, 'patch_installs': 950000},
      ]);
    });

    test('rejects an organization id with --enterprise-id', () async {
      when(() => h.argResults.rest).thenReturn(['42']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          'Pass an organization id or --enterprise-id, not both: '
          '--enterprise-id already covers every organization in the '
          'enterprise.',
        ),
      ).called(1);
      verifyNever(h.codePushClientWrapper.getEnterprises);
    });

    test('rejects --org-id with --enterprise-id', () async {
      when(() => h.argResults['org-id']).thenReturn('42');
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(h.codePushClientWrapper.getEnterprises);
    });

    test('reports a failed fetch', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseBilling(enterpriseId: 7),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch usage for enterprise 7.',
      );
    });
  });
}
