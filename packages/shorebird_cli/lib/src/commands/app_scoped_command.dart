import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// Help text for `--flavor` on commands that act on an existing app rather
/// than building one.
const appScopedFlavorHelp =
    'The product flavor whose app ID to use from shorebird.yaml '
    '(e.g. "prod"). Ignored when --app-id is passed.';

/// Shared `--app-id` and `--flavor` options for commands that act on an
/// existing app, and the logic that turns them into an app ID.
///
/// Call [addAppScopeOptions] from the command's constructor, then
/// [resolveAppId] from `run`.
mixin AppScopedCommand on ShorebirdCommand {
  /// Adds the `--app-id` and `--flavor` options that [resolveAppId] reads.
  void addAppScopeOptions() {
    argParser
      ..addOption(
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(CommonArguments.flavorArg.name, help: appScopedFlavorHelp);
  }

  /// Resolves the app ID from `--app-id` or `shorebird.yaml`, validating
  /// preconditions in the process.
  ///
  /// Returns `(appId: <id>, errorCode: null)` on success, or
  /// `(appId: '', errorCode: <code>)` if precondition validation failed or
  /// `--flavor` names a flavor shorebird.yaml doesn't define.
  Future<({String appId, int? errorCode})> resolveAppId() async {
    final explicitAppId = results[CommonArguments.appIdArg.name] as String?;
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: explicitAppId == null,
      );
    } on PreconditionFailedException catch (error) {
      return (appId: '', errorCode: error.exitCode.code);
    }
    if (explicitAppId != null) return (appId: explicitAppId, errorCode: null);

    final flavor = results.findOption(
      CommonArguments.flavorArg.name,
      argParser: argParser,
    );
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final flavorError = shorebirdYaml.unknownFlavorError(flavor);
    if (flavorError != null) {
      return (appId: '', errorCode: reportError(message: flavorError));
    }
    return (appId: shorebirdYaml.getAppId(flavor: flavor), errorCode: null);
  }
}
