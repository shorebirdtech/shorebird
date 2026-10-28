import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();

  group(OrgsCommand, () {
    late OrgsCommand command;

    setUp(() {
      command = OrgsCommand();
    });

    test('lists, creates, shows and renames organizations', () {
      expect(
        command.subcommands.keys,
        containsAll(['create', 'get', 'list', 'members', 'update']),
      );
    });

    test('accepts the spellings agents guess', () {
      expect(command.aliases, ['organizations', 'org', 'teams']);
    });

    test('lists organizations with no subcommand', () {
      expect(command.defaultSubcommand, 'list');
    });
  });

  group(AccountOrgsCommand, () {
    test('stays under account, hidden, for existing scripts', () {
      final orgs = AccountCommand().subcommands['orgs'];
      expect(orgs, isA<AccountOrgsCommand>());
      expect(orgs!.hidden, isTrue);
    });

    test('names the command that replaced it', () async {
      final logger = MockShorebirdLogger();
      final shorebirdValidator = MockShorebirdValidator();
      final codePushClientWrapper = MockCodePushClientWrapper();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        codePushClientWrapper.getOrganizationMemberships,
      ).thenAnswer((_) async => []);
      final result = await runScoped(
        () => (AccountOrgsCommand()..testArgResults = MockArgResults()).run(),
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => false),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
      expect(result, ExitCode.success.code);
      verify(
        () => logger.info(
          '`shorebird account orgs` is now `shorebird orgs list`.',
        ),
      ).called(1);
    });
  });
}
