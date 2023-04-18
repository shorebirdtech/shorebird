import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/flutter_validation_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template build_command}
///
/// `shorebird build`
/// Build a new release of your application.
/// {@endtemplate}
class BuildCommand extends ShorebirdCommand
    with ShorebirdValidationMixin, ShorebirdConfigMixin, ShorebirdBuildMixin {
  /// {@macro build_command}
  BuildCommand({required super.logger}) {
    addSubcommand(
      BuildApkCommand(
        auth: auth,
        logger: logger,
        runProcess: runProcess,
        validators: validators,
      ),
    );
    addSubcommand(
      BuildAppBundleCommand(
        auth: auth,
        logger: logger,
        runProcess: runProcess,
        validators: validators,
      ),
    );
  }

  @override
  String get description => 'Build a new release of your application.';

  @override
  String get name => 'build';
}
