import 'package:args/command_runner.dart';
import 'package:shorebird_ci/src/commands/commands.dart';

/// The shorebird_ci command runner.
class ShorebirdCiCommandRunner extends CommandRunner<int> {
  /// Creates a [ShorebirdCiCommandRunner].
  ShorebirdCiCommandRunner()
    : super('shorebird_ci', 'CI tooling for Dart/Flutter monorepos') {
    addCommand(AffectedPackagesCommand());
    addCommand(FlutterVersionCommand());
    addCommand(GenerateCommand());
    addCommand(UpdateActionsCommand());
    addCommand(VerifyCommand());
  }
}
