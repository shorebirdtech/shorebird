import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template flutter_versions_command}
/// `shorebird flutter versions`
/// Manage your Shorebird Flutter versions.
/// {@endtemplate}
class FlutterVersionsCommand extends ShorebirdCommand {
  /// {@macro flutter_versions_command}
  FlutterVersionsCommand() {
    addSubcommand(FlutterVersionsListCommand());
  }

  @override
  String get description => 'Manage your Shorebird Flutter versions.';

  @override
  String get name => 'versions';
}
