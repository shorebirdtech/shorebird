import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template build_command}
///
/// `shorebird build`
/// Build a new release of your application.
/// {@endtemplate}
class BuildCommand extends ShorebirdCommand
    with ShorebirdValidationMixin, ShorebirdConfigMixin, ShorebirdBuildMixin {
  /// {@macro build_command}
  BuildCommand({required super.logger}) {
    addSubcommand(BuildApkCommand(logger: logger));
    addSubcommand(BuildAppBundleCommand(logger: logger));
    addSubcommand(BuildIpaCommand(logger: logger));
  }

  @override
  String get description => 'Build a new release of your application.';

  @override
  String get name => 'build';
}
