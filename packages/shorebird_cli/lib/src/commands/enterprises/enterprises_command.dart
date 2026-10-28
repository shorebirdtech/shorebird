import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template enterprises_command}
/// `shorebird enterprises`
/// Commands for the enterprises you belong to.
/// {@endtemplate}
class EnterprisesCommand extends ShorebirdCommand {
  /// {@macro enterprises_command}
  EnterprisesCommand() {
    addSubcommand(EnterprisesGetCommand());
    addSubcommand(EnterprisesListCommand());
  }

  @override
  String get name => 'enterprises';

  @override
  List<String> get aliases => const ['enterprise'];

  @override
  String get description =>
      'List and inspect your enterprises. With no subcommand, lists them '
      '(the same as `shorebird enterprises list`).\n\n'
      'An enterprise holds several organizations. To act on all of them, '
      'pass --enterprise-id to `orgs list`, `apps list` or `members`.';

  @override
  String get defaultSubcommand => 'list';
}
