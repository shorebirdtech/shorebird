import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
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

  group(OrgsUsageCommand, () {
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
    late OrgsUsageCommand command;

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
      command = runWithOverrides(OrgsUsageCommand.new)
        ..testArgResults = argResults;

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

    test('is under orgs, and hidden under account and the top level', () {
      expect(OrgsCommand().subcommands['usage'], isA<OrgsUsageCommand>());
      final accountUsage = AccountCommand().subcommands['usage'];
      expect(accountUsage, isA<AccountUsageCommand>());
      expect(accountUsage!.hidden, isTrue);
      expect(TopLevelUsageCommand().hidden, isTrue);
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
}
