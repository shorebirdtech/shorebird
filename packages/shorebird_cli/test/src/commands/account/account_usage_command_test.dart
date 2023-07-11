import 'package:intl/intl.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:money2/money2.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  late Auth auth;
  late CodePushClientWrapper codePushClientWrapper;
  late Logger logger;
  late Progress progress;

  late AccountUsageCommand command;

  group(AccountUsageCommand, () {
    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper)
        },
      );
    }

    setUp(() {
      auth = _MockAuth();
      codePushClientWrapper = _MockCodePushClientWrapper();
      logger = _MockLogger();
      progress = _MockProgress();

      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      command = runWithOverrides(AccountUsageCommand.new);
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits with code 67 when user is not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.noUser.code);

      verify(
        () => logger.err(any(that: contains('You must be logged in to run'))),
      ).called(1);
    });

    test('exits with code 0 when usage is fetched.', () async {
      final usage = GetUsageResponse(
        plan: ShorebirdPlan(
          name: 'Team',
          monthlyCost: Money.fromIntWithCurrency(2000, usd),
          patchInstallLimit: 1000,
          maxTeamSize: 1,
        ),
        apps: const [
          AppUsage(
            id: 'test-app-id',
            name: 'test app 2',
            patchInstallCount: 42,
          ),
          AppUsage(
            id: 'test-app-id',
            name: 'test app 2',
            patchInstallCount: 42,
          ),
        ],
        patchInstallLimit: 20000,
        currentPeriodCost: Money.fromIntWithCurrency(2000, usd),
        currentPeriodStart: DateTime(2023),
        currentPeriodEnd: DateTime(2023, 2),
      );
      when(
        () => codePushClientWrapper.getUsage(),
      ).thenAnswer((_) async => usage);

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.success.code);
      verify(() => logger.info('📈 Usage')).called(1);
      verify(
        () => logger.info(
          any(
            that: contains('''

You are on the ${lightCyan.wrap('Team')} plan.

┌────────────┬────────────────┐
│ App        │ Patch Installs │
├────────────┼────────────────┤
│ test app 2 │ 42             │
├────────────┼────────────────┤
│ test app 2 │ 42             │
├────────────┼────────────────┤
│ Total      │ 84             │
└────────────┴────────────────┘

${styleBold.wrap('${lightCyan.wrap('19916')} patch installs remaining in the current billing period.')}

Current Billing Period: ${lightCyan.wrap(DateFormat.yMMMd().format(usage.currentPeriodStart))} - ${lightCyan.wrap(DateFormat.yMMMd().format(usage.currentPeriodEnd))}
Month-to-date cost: ${lightCyan.wrap(r'$20.00')}

${styleBold.wrap('*Usage data is not reported in real-time and may be delayed by up to 48 hours.')}'''),
          ),
        ),
      ).called(1);
    });

    test('exits with code 0 when usage is fetched (unlimited).', () async {
      final usage = GetUsageResponse(
        plan: ShorebirdPlan(
          name: 'Hobby',
          monthlyCost: Money.fromIntWithCurrency(0, usd),
          patchInstallLimit: 1000,
          maxTeamSize: 1,
        ),
        apps: const [
          AppUsage(
            id: 'test-app-id',
            name: 'test app 2',
            patchInstallCount: 42,
          ),
          AppUsage(
            id: 'test-app-id',
            name: 'test app 2',
            patchInstallCount: 42,
          ),
        ],
        currentPeriodCost: Money.fromIntWithCurrency(0, usd),
        currentPeriodStart: DateTime(2023),
        currentPeriodEnd: DateTime(2023, 2),
      );
      when(
        () => codePushClientWrapper.getUsage(),
      ).thenAnswer((_) async => usage);

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.success.code);
      verify(() => logger.info('📈 Usage')).called(1);
      verify(
        () => logger.info(
          any(
            that: contains('''

You are on the ${lightCyan.wrap('Hobby')} plan.

┌────────────┬────────────────┐
│ App        │ Patch Installs │
├────────────┼────────────────┤
│ test app 2 │ 42             │
├────────────┼────────────────┤
│ test app 2 │ 42             │
├────────────┼────────────────┤
│ Total      │ 84             │
└────────────┴────────────────┘

${styleBold.wrap('${lightCyan.wrap('∞')} patch installs remaining in the current billing period.')}

Current Billing Period: ${lightCyan.wrap(DateFormat.yMMMd().format(usage.currentPeriodStart))} - ${lightCyan.wrap(DateFormat.yMMMd().format(usage.currentPeriodEnd))}
Month-to-date cost: ${lightCyan.wrap(r'$0.00')}

${styleBold.wrap('*Usage data is not reported in real-time and may be delayed by up to 48 hours.')}'''),
          ),
        ),
      ).called(1);
    });
  });
}
