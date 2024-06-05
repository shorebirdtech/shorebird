import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

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
  String get description => '''
Build a new release of your application.

Builds created with this command will not be patchable. If you need to create a patchable build, use the `shorebird release` command instead.`''';

  @override
  String get name => 'build-internal';

  @override
  bool get hidden => true;
}
