import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
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
  Future<void> assertPreconditions() => assertBuildPreconditions(
    validators: applePlatformValidators,
    supportedOperatingSystems: {NativePlatform.macOS},
  );

  @override
  Future<UpdateReleaseMetadata> updatedReleaseMetadata(
    UpdateReleaseMetadata metadata,
  ) async => metadata.copyWith(
    environment: metadata.environment.copyWith(
      xcodeVersion: await xcodeBuild.version(),
    ),
  );
}
