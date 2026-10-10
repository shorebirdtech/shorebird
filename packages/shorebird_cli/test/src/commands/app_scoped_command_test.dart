import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:test/test.dart';

import '../mocks.dart';

class _TestCommand extends ShorebirdCommand with AppScopedCommand {
  _TestCommand() {
    addAppScopeOptions();
  }

  @override
  String get name => 'test';

  @override
  String get description => 'A command for testing AppScopedCommand.';
}

void main() {
  group(AppScopedCommand, () {
    const appId = 'test-app-id';
    const flavoredAppId = 'flavored-app-id';
    const shorebirdYaml = ShorebirdYaml(
      appId: appId,
      flavors: {'staging': flavoredAppId},
    );

    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late _TestCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    /// A [command] whose results come from parsing [args].
    _TestCommand commandWith(List<String> args) =>
        command..testArgResults = command.argParser.parse(args);

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      command = _TestCommand();

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});
    });

    test('adds --app-id and --flavor', () {
      expect(command.argParser.options, contains('app-id'));
      expect(
        command.argParser.options['flavor']!.help,
        equals(appScopedFlavorHelp),
      );
    });

    group('resolveAppId', () {
      test('uses the app id from shorebird.yaml by default', () async {
        final result = await runWithOverrides(commandWith([]).resolveAppId);
        expect(result, equals((appId: appId, errorCode: null)));
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
            checkShorebirdInitialized: true,
          ),
        ).called(1);
      });

      test('uses the flavored app id when --flavor is passed', () async {
        final result = await runWithOverrides(
          commandWith(['--flavor', 'staging']).resolveAppId,
        );
        expect(result, equals((appId: flavoredAppId, errorCode: null)));
      });

      test('uses --app-id without requiring shorebird.yaml', () async {
        final result = await runWithOverrides(
          commandWith(['--app-id', 'explicit-app-id']).resolveAppId,
        );
        expect(result, equals((appId: 'explicit-app-id', errorCode: null)));
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
          ),
        ).called(1);
        verifyNever(() => shorebirdEnv.getShorebirdYaml());
      });

      test('prefers --app-id over --flavor', () async {
        final result = await runWithOverrides(
          commandWith([
            '--app-id',
            'explicit-app-id',
            '--flavor',
            'staging',
          ]).resolveAppId,
        );
        expect(result, equals((appId: 'explicit-app-id', errorCode: null)));
      });

      test('returns the exit code when preconditions fail', () async {
        final exception = ShorebirdNotInitializedException();
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(exception);

        final result = await runWithOverrides(commandWith([]).resolveAppId);
        expect(result, equals((appId: '', errorCode: exception.exitCode.code)));
      });
    });
  });
}
