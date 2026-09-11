import 'package:mason_logger/mason_logger.dart';
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Shared logic for Apple-platform releasers (iOS, macOS, iOS framework).
///
/// Concrete releasers supply the platform-specific validators via
/// [applePlatformValidators]; the mixin handles the common preconditions and
/// metadata enrichment that every Apple release performs.
mixin AppleReleaserMixin on Releaser {
  /// The doctor validators that should run before this Apple release.
  List<Validator> get applePlatformValidators;

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: applePlatformValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }
  }

  @override
  Future<UpdateReleaseMetadata> updatedReleaseMetadata(
    UpdateReleaseMetadata metadata,
  ) async => metadata.copyWith(
    environment: metadata.environment.copyWith(
      xcodeVersion: await xcodeBuild.version(),
    ),
  );

  /// Rejects `--release-version`, which is only valid for releases whose
  /// version cannot be inferred from the built artifact (aar, ios-framework).
  /// Call from `assertArgsAreValid` in iOS/macOS releasers.
  void assertReleaseVersionFlagNotProvided() {
    if (argResults.wasParsed('release-version')) {
      logger.err(
        '''
The "--release-version" flag is only supported for aar and ios-framework releases.

To change the version of this release, change your app's version in your pubspec.yaml.''',
      );
      throw ProcessExit(ExitCode.usage.code);
    }
  }
}
