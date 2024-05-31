import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template flutter_command}
/// `shorebird flutter`
/// Manage your Shorebird Flutter installation.
/// {@endtemplate}
class FlutterCommand extends ShorebirdCommand {
  /// {@macro flutter_command}
  FlutterCommand() {
    addSubcommand(FlutterVersionsCommand());
  }

  @override
  String get description => 'Manage your Shorebird Flutter installation.';

  @override
  String get name => 'flutter';
}
