import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/apple_patcher_mixin.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// {@template macos_patcher}
/// Functions to create and apply patches to a macOS release.
/// {@endtemplate}
class MacosPatcher extends Patcher
    with ApplePatcherMixin, ApplePodfileLockPatcherMixin {
  /// {@macro macos_patcher}
  MacosPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  // The elf snapshot built for Apple Silicon macs.
  String get _arm64AotOutputPath =>
      p.join(shorebirdEnv.buildDirectory.path, 'out.arm64.aot');

  // The elf snapshot built for Intel macs.
  String get _x64AotOutputPath =>
      p.join(shorebirdEnv.buildDirectory.path, 'out.x64.aot');

  String get _appDillCopyPath =>
      p.join(shorebirdEnv.buildDirectory.path, 'app.dill');

  @override
  ReleaseType get releaseType => ReleaseType.macos;

  /// Whether to codesign the release.
  bool get codesign => argResults['codesign'] == true;

  @override
  String get primaryReleaseArtifactArch => 'app';

  @override
  String? get supplementaryReleaseArtifactArch => 'macos_supplement';

  @override
  List<Validator> get applePlatformValidators => doctor.macosCommandValidators;

  @override
  String? get localPodfileLockHash => shorebirdEnv.macosPodfileLockHash;

  @override
  String get podfileLockRelativePath => 'macos/Podfile.lock';

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final (flutterVersionAndRevision, flutterVersion) = await (
      shorebirdFlutter.getVersionAndRevision(),
      shorebirdFlutter.getVersion(),
    ).wait;

    if ((flutterVersion ?? minimumSupportedMacosFlutterVersion) <
        minimumSupportedMacosFlutterVersion) {
      logger.err('''
macOS patches are not supported with Flutter versions older than $minimumSupportedMacosFlutterVersion.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''');
      throw ProcessExit(ExitCode.software.code);
    }

    final buildArgs = [
      ...argResults.forwardedArgs,
      ...extraBuildArgs,
      ...buildNameAndNumberArgsFromReleaseVersion(releaseVersion),
    ];

    // If buildMacos is called with a different codesign value than the
    // release was, we will erroneously report native diffs.
    final macosBuildResult = await artifactBuilder.buildMacos(
      codesign: codesign,
      flavor: flavor,
      target: target,
      args: buildArgs,
      base64PublicKey: argResults.encodedPublicKey,
    );

    if (splitDebugInfoPath != null) {
      Directory(splitDebugInfoPath!).createSync(recursive: true);
    }
    await artifactBuilder.buildElfAotSnapshot(
      appDillPath: macosBuildResult.kernelFile.path,
      outFilePath: _arm64AotOutputPath,
      genSnapshotArtifact: ShorebirdArtifact.genSnapshotMacosArm64,
      additionalArgs: [
        ...ApplePatcherMixin.splitDebugInfoArgs(splitDebugInfoPath),
        ...obfuscationGenSnapshotArgs,
      ],
    );

    if (!File(_arm64AotOutputPath).existsSync()) {
      throw Exception('Failed to build arm64 AOT snapshot');
    }

    await artifactBuilder.buildElfAotSnapshot(
      appDillPath: macosBuildResult.kernelFile.path,
      outFilePath: _x64AotOutputPath,
      genSnapshotArtifact: ShorebirdArtifact.genSnapshotMacosX64,
      additionalArgs: [
        ...ApplePatcherMixin.splitDebugInfoArgs(splitDebugInfoPath),
        ...obfuscationGenSnapshotArgs,
      ],
    );

    if (!File(_x64AotOutputPath).existsSync()) {
      throw Exception('Failed to build x64 AOT snapshot');
    }

    // Copy the kernel file to the build directory so that it can be used
    // to generate a patch.
    macosBuildResult.kernelFile.copySync(_appDillCopyPath);

    final appPath = artifactManager.getMacOSAppDirectory(flavor: flavor)!.path;
    final tempDir = await Directory.systemTemp.createTemp();
    final zippedApp = File(p.join(tempDir.path, '${p.basename(appPath)}.zip'));
    await ditto.archive(
      source: appPath,
      destination: zippedApp.path,
      // keepParent is false here in order to ensure the directory structure of
      // this zip file matches what will be provided to the [AppleArchiveDiffer]
      // (which uses package:archive to stream zip file contents).
    );
    return zippedApp;
  }

  Future<PatchArtifactBundle> _createPatchArtifactBundle({
    required File releaseArtifact,
    required File patchArtifact,
    required Arch arch,
  }) async {
    final patchFilePath = await artifactManager.createDiff(
      releaseArtifactPath: releaseArtifact.path,
      patchArtifactPath: patchArtifact.path,
    );

    final patchFile = File(patchFilePath);
    final patchFileSize = patchFile.statSync().size;
    final hash = sha256.convert(patchArtifact.readAsBytesSync()).toString();
    final hashSignature = await signHash(hash);

    return PatchArtifactBundle(
      arch: arch.arch,
      path: patchFilePath,
      hash: hash,
      size: patchFileSize,
      hashSignature: hashSignature,
      podfileLockHash: shorebirdEnv.macosPodfileLockHash,
    );
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    Directory? supplementDirectory,
  }) async {
    final unzipProgress = logger.progress('Extracting release artifact');
    final releaseAppDirectory = Directory.systemTemp.createTempSync();
    await ditto.extract(
      source: releaseArtifact.path,
      destination: releaseAppDirectory.path,
    );
    unzipProgress.complete();

    final releaseArtifactFile = File(
      p.join(
        releaseAppDirectory.path,
        'Contents',
        'Frameworks',
        'App.framework',
        'App',
      ),
    );

    final createDiffProgress = logger.progress('Creating patch artifacts');
    final arm64Bundle = await _createPatchArtifactBundle(
      releaseArtifact: releaseArtifactFile,
      patchArtifact: File(_arm64AotOutputPath),
      arch: Arch.arm64,
    );
    final x64Bundle = await _createPatchArtifactBundle(
      releaseArtifact: releaseArtifactFile,
      patchArtifact: File(_x64AotOutputPath),
      arch: Arch.x86_64,
    );
    createDiffProgress.complete();

    return {Arch.x86_64: x64Bundle, Arch.arm64: arm64Bundle};
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    final appPath = artifactManager.getMacOSAppDirectory()?.path;
    if (appPath == null) {
      logger.err('Unable to find .app directory');
      throw ProcessExit(ExitCode.software.code);
    }

    final plistFile = File(p.join(appPath, 'Contents', 'Info.plist'));
    if (!plistFile.existsSync()) {
      logger.err('No Info.plist file found at ${plistFile.path}.');
      throw ProcessExit(ExitCode.software.code);
    }

    final plist = Plist(file: plistFile);
    try {
      return plist.versionNumber;
    } on Exception catch (error) {
      logger.err(
        'Failed to determine release version from ${plistFile.path}: $error',
      );
      throw ProcessExit(ExitCode.software.code);
    }
  }
}
