import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/apple_build_helpers.dart';
import 'package:shorebird_cli/src/commands/patch/macos_patcher.dart';
import 'package:shorebird_cli/src/commands/release/apple_releaser_mixin.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template macos_releaser}
/// Functions to build and publish a macOS release.
/// {@endtemplate}
class MacosReleaser extends Releaser with AppleReleaserMixin {
  /// {@macro macos_releaser}
  MacosReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  /// The architectures the built `App.framework/App` binary carries slices
  /// for, once [buildReleaseArtifacts] has inspected it.
  Set<Arch>? _builtArchitectures;

  @override
  ReleaseType get releaseType => ReleaseType.macos;

  @override
  Map<Arch, String> get debugInfoFileNames => const {
    Arch.arm64: MacosPatcher.arm64SplitDebugInfoFileName,
    Arch.x86_64: MacosPatcher.x64SplitDebugInfoFileName,
  };

  @override
  Set<Arch> get builtArchitectures =>
      _builtArchitectures ?? super.builtArchitectures;

  @override
  String get supplementPlatformSubdir => 'macos';

  @override
  String get supplementArtifactArch => 'macos_supplement';

  @override
  String get artifactDisplayName => 'macOS app';

  @override
  List<Validator> get applePlatformValidators => doctor.macosCommandValidators;

  @override
  Future<void> assertArgsAreValid() async {
    assertReleaseVersionFlagNotProvided();
    assertMacosCodesignNotDisabled(argResults);
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    _builtArchitectures = null;
    await runReleaseBuild(
      (buildArgs, base64PublicKey) => artifactBuilder.buildMacos(
        flavor: flavor,
        target: target,
        args: buildArgs,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
      ),
    );

    final appDirectory = artifactManager.getMacOSAppDirectory(flavor: flavor);
    if (appDirectory == null) {
      throw CommandError(
        message: 'Unable to find the .app directory in the macOS build output.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }

    _builtArchitectures = MachO.architectures(
      File(
        p.join(
          appDirectory.path,
          'Contents',
          'Frameworks',
          'App.framework',
          'App',
        ),
      ),
    );

    return appDirectory;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async => readReleaseVersionFromInfoPlist(
    File(p.join(releaseArtifactRoot.path, 'Contents', 'Info.plist')),
    hint: 'Re-run with --verbose to see the build output.',
  );

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final appDirectory = artifactManager.getMacOSAppDirectory(flavor: flavor);
    if (appDirectory == null) {
      throw CommandError(
        message: 'Unable to find the .app directory in the macOS build output.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }

    await codePushClientWrapper.createMacosReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      appPath: appDirectory.path,
      podfileLockHash: shorebirdEnv.macosPodfileLockHash,
      signing: signing,
    );
  }

  @override
  String get postReleaseInstructions =>
      '''

macOS app created at ${artifactManager.getMacOSAppDirectory(flavor: flavor)!.path}.

To distribute your app outside the Mac App Store, sign it with your Developer ID and notarize it: ${link(uri: Uri.parse('https://docs.shorebird.dev/code-push/release/#notarize-a-macos-app'))}
${shorebirdArtifacts.macosPatchesSurviveResigning ? '' : _resigningNote}''';

  String get _resigningNote =>
      '''

${styleBold.wrap('Note:')} Patches to this release may fail to install after the app is re-signed (Developer ID or a Mac App Store .pkg). Release with Flutter 3.47.7 or newer to avoid this. See ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/3223'))} for more information.
''';
}
