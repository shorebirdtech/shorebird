import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
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
      final usage = [
        const AppUsage(
          id: 'test-app-id',
          name: 'test-app-name',
          patchInstallCount: 42,
        ),
      ];
      when(
        () => codePushClientWrapper.getUsage(),
      ).thenAnswer((_) async => usage);

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.success.code);
      verify(() => logger.info('📈 Usage')).called(1);
      verify(
        () => logger.info('''
┌──────────────────────┐
│ Total Patch Installs │
├──────────────────────┤
│ 42                   │
└──────────────────────┘'''),
      ).called(1);
    });
  });
}
