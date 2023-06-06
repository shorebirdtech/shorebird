import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';

/// {@template build_command}
/// `shorebird build`
/// Build a new release of your application.
/// {@endtemplate}
class BuildCommand extends ShorebirdCommand {
  /// {@macro build_command}
  BuildCommand({required super.logger}) {
    addSubcommand(BuildAarCommand(logger: logger));
    addSubcommand(BuildApkCommand(logger: logger));
    addSubcommand(BuildAppBundleCommand(logger: logger));
    addSubcommand(BuildIpaCommand(logger: logger));
  }

  @override
  String get description => 'Build a new release of your application.';

  @override
  String get name => 'build';
}
