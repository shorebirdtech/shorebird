import 'package:shorebird_cli/src/commands/auth/auth.dart';
import 'package:shorebird_cli/src/commands/login_command.dart';
import 'package:shorebird_cli/src/commands/logout_command.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(AuthCommand, () {
    late AuthCommand command;

    setUp(() {
      command = AuthCommand();
    });

    test('has a name and description', () {
      expect(command.name, equals('auth'));
      expect(command.description, isNotEmpty);
    });

    test('has status and token subcommands', () {
      expect(command.subcommands['status'], isA<AuthStatusCommand>());
      expect(command.subcommands['token'], isA<AuthTokenCommand>());
    });

    test('accepts print-access-token for token, keeping stdout clean', () {
      final alias = command.subcommands['print-access-token'];
      expect(alias, isA<AuthTokenCommand>());
      expect((alias! as AuthTokenCommand).reservesStdout, isTrue);
    });

    test('has hidden login and logout aliases', () {
      final login = command.subcommands['login'];
      final logout = command.subcommands['logout'];
      expect(login, isA<LoginCommand>());
      expect(logout, isA<LogoutCommand>());
      expect(login!.hidden, isTrue);
      expect(logout!.hidden, isTrue);
    });
  });
}
