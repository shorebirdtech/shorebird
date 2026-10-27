import 'package:shorebird_cli/src/commands/finish_in_console.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';

/// {@template console_page_command}
/// A command that only opens the Shorebird console page where [action] is
/// done, because the CLI does not do it (ADR-0026). It sends no API request.
/// {@endtemplate}
class ConsolePageCommand extends ShorebirdCommand with FinishInConsole {
  /// {@macro console_page_command}
  ConsolePageCommand({
    required this.name,
    required this.action,
    required this.path,
    required this.why,
  });

  @override
  final String name;

  /// What the user does on the page, completing "to ...", such as "delete
  /// your account".
  final String action;

  /// The console path of the page, such as `account/api-keys`.
  final String path;

  /// Why the CLI leaves [action] to the console.
  final String why;

  @override
  String get description =>
      'Opens the Shorebird console to $action.\n\n'
      '$why When not running interactively (no terminal, CI, or --json), '
      'this prints the console URL and exits with an error.';

  @override
  Future<int> run() async =>
      finishInConsole(action: action, url: ShorebirdWebConsole.uri(path));
}
