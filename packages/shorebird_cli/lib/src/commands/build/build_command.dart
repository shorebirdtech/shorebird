import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';

/// {@template build_command}
/// `shorebird build`
/// Build a new release of your application.
/// {@endtemplate}
class BuildCommand extends ShorebirdCommand {
  /// {@macro build_command}
  BuildCommand() {
    addSubcommand(BuildAarCommand());
    addSubcommand(BuildApkCommand());
    addSubcommand(BuildAppBundleCommand());
    addSubcommand(BuildIpaCommand());
  }

  @override
  String get description => 'Build a new release of your application.';

  @override
  String get name => 'build';

  @override
  bool get hidden => true;
}
