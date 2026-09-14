import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// {@template flavor_validator}
/// Verifies that the flavors in the Shorebird configuration match the
/// --flavor argument provided by the user. This throws a [ProcessExit] if:
///  1. The project has flavors but no `--flavor` argument was provided.
///  2. The project does not have flavors but a `--flavor` argument was
///     provided.
///  3. The project has flavors and a `--flavor` argument was provided, but
///     the flavor does not exist in the project.
/// {@endtemplate}
class FlavorValidator extends Validator {
  /// {@macro flavor_validator}
  FlavorValidator({required this.flavorArg});

  /// The flavor argument provided by the user via `--flavor`.
  final String? flavorArg;

  @override
  String get description => 'Flavor argument is valid for project flavors';

  @override
  Future<List<ValidationIssue>> validate() async {
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final projectFlavors = shorebirdYaml.flavors;
    if (projectFlavors == null && flavorArg != null) {
      return [
        ValidationIssue.error(
          message:
              '''The project does not have any flavors defined (no "flavors" in shorebird.yaml), but --flavor was provided. Re-run without --flavor, or run "shorebird init" to detect flavors.''',
        ),
      ];
    }

    if (projectFlavors != null && flavorArg == null) {
      return [
        ValidationIssue.warning(
          message:
              '''
The project has flavors ${projectFlavors.keys.join(', ')}, but no --flavor argument was provided.
The default app id ${shorebirdYaml.appId} will be used. Pass --flavor=<name> to target a flavor.''',
        ),
      ];
    }

    if (projectFlavors != null &&
        flavorArg != null &&
        !projectFlavors.containsKey(flavorArg)) {
      return [
        ValidationIssue.error(
          message:
              '''This project does not have a flavor named "$flavorArg". Pass one of: ${projectFlavors.keys.join(', ')} (from "flavors" in shorebird.yaml).''',
        ),
      ];
    }

    return [];
  }
}
