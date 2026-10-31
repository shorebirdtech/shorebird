import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
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
///  4. [platformFlavors] is given and has no flavor matching `--flavor`, such
///     as an app with Android flavors whose Xcode project has no schemes.
/// {@endtemplate}
class FlavorValidator extends Validator {
  /// {@macro flavor_validator}
  FlavorValidator({
    required this.flavorArg,
    this.platformName,
    this.platformFlavors,
  });

  /// The flavor argument provided by the user via `--flavor`.
  final String? flavorArg;

  /// The name of the platform being built, as customers read it (`iOS`).
  final String? platformName;

  /// The flavors (lowercased) the platform's native project defines, or null
  /// when unknown. Shorebird only knows these for Apple platforms, from the
  /// Xcode schemes.
  final Set<String>? platformFlavors;

  @override
  String get description => 'Flavor argument is valid for project flavors';

  @override
  Future<List<ValidationIssue>> validate() async {
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final flavorError = shorebirdYaml.unknownFlavorError(flavorArg);
    if (flavorError != null) {
      return [ValidationIssue.error(message: flavorError)];
    }

    final flavor = flavorArg;
    final nativeFlavors = platformFlavors;
    if (flavor != null &&
        nativeFlavors != null &&
        !nativeFlavors.contains(flavor.toLowerCase())) {
      final fix = nativeFlavors.isEmpty
          ? 'or re-run without --flavor to use the default app id '
                '${shorebirdYaml.appId}'
          : 'or pass one of: ${nativeFlavors.join(', ')}';
      return [
        ValidationIssue.error(
          message:
              '''The $platformName project has no Xcode scheme for flavor "$flavor", so it cannot be built with --flavor=$flavor. Add a scheme named "$flavor" (see https://docs.shorebird.dev/code-push/guides/flavors/ios/), $fix.''',
        ),
      ];
    }

    final projectFlavors = shorebirdYaml.flavors;
    // A platform with no flavors of its own can only use the default app id,
    // so there is nothing to warn about.
    final platformHasFlavors = nativeFlavors?.isNotEmpty ?? true;
    if (projectFlavors != null && flavorArg == null && platformHasFlavors) {
      return [
        ValidationIssue.warning(
          message:
              '''
The project has flavors ${projectFlavors.keys.join(', ')}, but no --flavor argument was provided.
The default app id ${shorebirdYaml.appId} will be used. Pass --flavor=<name> to target a flavor.''',
        ),
      ];
    }

    return [];
  }
}
