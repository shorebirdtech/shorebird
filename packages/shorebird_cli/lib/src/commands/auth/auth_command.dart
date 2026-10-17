import 'package:shorebird_cli/src/commands/auth/auth.dart';
import 'package:shorebird_cli/src/commands/login_command.dart';
import 'package:shorebird_cli/src/commands/logout_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template auth_command}
/// `shorebird auth`
/// Commands for the credential the CLI authenticates with.
/// {@endtemplate}
class AuthCommand extends ShorebirdCommand {
  /// {@macro auth_command}
  AuthCommand() {
    addSubcommand(AuthStatusCommand());
    addSubcommand(AuthTokenCommand());
    addSubcommand(AuthLoginCommand());
    addSubcommand(AuthLogoutCommand());
  }

  @override
  String get name => 'auth';

  @override
  String get description =>
      'Show the credential the CLI authenticates with, or print its access '
      'token.';
}

/// {@template auth_login_command}
/// `shorebird auth login`, a hidden alias of `shorebird login`.
/// {@endtemplate}
class AuthLoginCommand extends LoginCommand {
  /// {@macro auth_login_command}
  AuthLoginCommand();

  @override
  bool get hidden => true;
}

/// {@template auth_logout_command}
/// `shorebird auth logout`, a hidden alias of `shorebird logout`.
/// {@endtemplate}
class AuthLogoutCommand extends LogoutCommand {
  /// {@macro auth_logout_command}
  AuthLogoutCommand();

  @override
  bool get hidden => true;
}
