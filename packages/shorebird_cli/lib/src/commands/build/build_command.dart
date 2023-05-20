import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/validators/shorebird_yaml_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// {@template build_command}
/// `shorebird build`
/// Build a new release of your application.
/// {@endtemplate}
class BuildCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro build_command}
  BuildCommand() {
    validators = _allValidators(baseValidators: validators);

    addSubcommand(BuildAarCommand());
    addSubcommand(BuildApkCommand());
    addSubcommand(BuildAppBundleCommand());
    addSubcommand(BuildIpaCommand());
  }

  late final List<Validator> _buildValidators = [
    ShorebirdYamlValidator(hasShorebirdYaml: () => hasShorebirdYaml),
    AndroidInternetPermissionValidator(),
  ];

  @override
  String get description => 'Build a new release of your application.';

  @override
  String get name => 'build';

  /// Creates a list that is the union of [baseValidators] and
  /// [_buildValidators].
  List<Validator> _allValidators({
    required List<Validator> baseValidators,
  }) {
    final missingValidators = _buildValidators
        .where(
          (runValidator) => baseValidators.none(
            (baseValidator) => baseValidator.id == runValidator.id,
          ),
        )
        .toList();

    return baseValidators + missingValidators;
  }
}
