import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/iterable.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template patcher}
/// Platform-specific functionality to create a patch.
/// {@endtemplate}
abstract class Patcher {
  /// {@macro patcher}
  Patcher({
    required this.argParser,
    required this.argResults,
    required this.flavor,
    required this.target,
  });

  /// Link percentage below which a warning is issued.
  static const double linkPercentageWarningThreshold = 90;

  /// The standard link percentage warning.
  static String lowLinkPercentageWarning(double linkPercentage) {
    return '''
${lightCyan.wrap('shorebird patch')} was only able to share ${linkPercentage.toStringAsFixed(1)}% of Dart code with the released app.
This is unexpected, and means the application may execute slower than expected after patching.
Please reach out to us over Discord or Email for help.
More info: ${troubleshootingUrl.toLink()}.
''';
  }

  /// The parser for the arguments passed to the command.
  final ArgParser argParser;

  /// The arguments passed to the command.
  final ArgResults argResults;

  /// The flavor of the release, if any.
  final String? flavor;

  /// The target script to run, if any.
  final String? target;

  /// Whether the release was built with obfuscation, so the patch must be
  /// too. Set by the patch command.
  bool obfuscate = false;

  /// The path to the release's obfuscation map, if the patch should reuse
  /// the release's obfuscated names. Set by the patch command. Only set when
  /// [obfuscate] is true and the release's Flutter supports loading the map.
  String? obfuscationMapPath;

  /// Extra build arguments injected by the patch command. These are included
  /// in the Flutter build command args by patchers. Currently used to inject
  /// obfuscation flags when the release was built with obfuscation.
  List<String> extraBuildArgs = const [];

  /// Additional gen_snapshot arguments needed to match the release's
  /// obfuscation flags. Used by Apple patchers for
  /// `ArtifactBuilder.buildElfAotSnapshot`
  /// and linker calls.
  List<String> get obfuscationGenSnapshotArgs => [
    if (obfuscate) ...[
      '--obfuscate',
      if (obfuscationMapPath != null)
        '--load-obfuscation-map=$obfuscationMapPath',
      // --dwarf-stack-traces must match the release build so the patch
      // produces the same stack trace format for correct symbolication.
      // --split-debug-info already implies --dwarf-stack-traces, so we only
      // need to pass it as a standalone flag when split debug info isn't used.
      if (splitDebugInfoPath == null) '--dwarf-stack-traces',
      // Strip DWARF debug info so obfuscated snapshots don't leak the
      // identifiers that obfuscation was meant to hide.
      '--strip',
    ],
  ];

  /// The minimum Flutter version a release must have been built with to be
  /// patched with this patcher.
  Version? get minimumFlutterVersion => null;

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// The identifier used for the "primary" release artifact, usually a bundle.
  /// For example, 'aab' for Android, 'xcarchive' for iOS.
  String get primaryReleaseArtifactArch;

  /// The identifier used for any supplementary release artifacts.
  String? get supplementaryReleaseArtifactArch => null;

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// Asserts that the command can be run.
  Future<void> assertPreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> assertArgsAreValid() async {}

  /// Whether `--release-version` must be passed when the version can't be
  /// prompted for.
  ///
  /// True for release types whose version can't be read back out of a built
  /// artifact ([extractReleaseVersionFromArtifact] is unimplemented). When
  /// running interactively the user picks the release instead; otherwise the
  /// patch command rejects a missing `--release-version` before building.
  bool get requiresReleaseVersionArg => false;

  /// Compares the release and patch artifacts to determine if the patch can be
  /// cleanly applied to the release.
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  });

  /// Builds the patch artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<File> buildPatchArtifact({String? releaseVersion});

  /// Determines the release version from the provided app artifact.
  Future<String> extractReleaseVersionFromArtifact(File artifact);

  /// Creates the patch artifacts required to apply a patch to a release.
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    Directory? supplementDirectory,
  });

  /// Updates the provided metadata to include patcher-specific fields.
  Future<CreatePatchMetadata> updatedCreatePatchMetadata(
    CreatePatchMetadata metadata,
  ) async {
    return metadata;
  }

  /// Uploads the patch artifacts to the CodePush server.
  Future<Patch> uploadPatchArtifacts({
    required String appId,
    required int releaseId,
    required Map<String, dynamic> metadata,
    required Map<Arch, PatchArtifactBundle> artifacts,
    required DeploymentTrack track,
  }) {
    return codePushClientWrapper.publishPatch(
      appId: appId,
      releaseId: releaseId,
      metadata: metadata,
      platform: releaseType.releasePlatform,
      track: track,
      patchArtifactBundles: artifacts,
    );
  }

  /// Whether to allow changes in assets (--allow-asset-diffs).
  bool get allowAssetDiffs => argResults['allow-asset-diffs'] == true;

  /// Whether to allow changes in native code (--allow-native-diffs).
  bool get allowNativeDiffs => argResults['allow-native-diffs'] == true;

  /// Whether to print every differing instruction (--show-dex-diff).
  bool get showDexDiff => argResults['show-dex-diff'] == true;

  /// Returns a function that signs data, or null if no signing is configured.
  Future<String> Function(String)? _resolveSigner() {
    final privateKeyFile = argResults.file(CommonArguments.privateKeyArg.name);
    if (privateKeyFile != null) {
      return (hash) async =>
          codeSigner.sign(message: hash, privateKeyPemFile: privateKeyFile);
    }

    final signCmd = argResults[CommonArguments.signCmd.name] as String?;
    if (signCmd != null) {
      return (hash) async {
        try {
          return await codeSigner.signWithCmd(data: hash, command: signCmd);
        } on ProcessException catch (e) {
          logger.err(
            'Failed to run --${CommonArguments.signCmd.name}: ${e.message}',
          );
          throw ProcessExit(ExitCode.software.code);
        } on FormatException catch (e) {
          logger.err(
            '--${CommonArguments.signCmd.name} produced invalid output: '
            '${e.message}',
          );
          throw ProcessExit(ExitCode.software.code);
        }
      };
    }

    return null;
  }

  /// The managed public key (PEM) the release being patched embeds, which
  /// the patch builds against. Null unless the release is managed-signed.
  String? releaseManagedPublicKeyPem;

  /// Gets the base64-encoded public key the patch build embeds.
  ///
  /// A patch builds against the key its release embeds, so its build matches
  /// the release's. For a managed release that is the release's managed key;
  /// otherwise the key from --public-key-path or --public-key-cmd, the same
  /// way releases do.
  ///
  /// Returns null if no public key is configured.
  Future<String?> getEncodedPublicKey() async {
    if (releaseManagedPublicKeyPem case final pem?) {
      return codeSigner.base64PublicKeyFromPem(pem);
    }
    return argResults.getEncodedPublicKey();
  }

  /// Returns the public key PEM from the configured source, or null.
  Future<String?> _resolvePublicKeyPem() async {
    try {
      return await argResults.resolvePublicKeyPem();
    } on ProcessException catch (e) {
      logger.err(
        'Failed to run '
        '--${CommonArguments.publicKeyCmd.name}: ${e.message}',
      );
      throw ProcessExit(ExitCode.software.code);
    } on FormatException catch (e) {
      final source = argResults.wasParsed(CommonArguments.publicKeyArg.name)
          ? '--${CommonArguments.publicKeyArg.name} file'
          : '--${CommonArguments.publicKeyCmd.name} output';
      logger.err('The $source ${e.message}');
      throw ProcessExit(ExitCode.software.code);
    }
  }

  /// Signs a hash using the configured signing method.
  ///
  /// Returns null if no signing is configured.
  Future<String?> signHash(String hash) async {
    final signer = _resolveSigner();
    if (signer == null) return null;

    final signature = await signer(hash);
    final publicKeyPem = await _resolvePublicKeyPem();

    if (publicKeyPem == null) {
      logger.err(
        'A public key is required for code signing. '
        'Provide --${CommonArguments.publicKeyArg.name} or '
        '--${CommonArguments.publicKeyCmd.name}.',
      );
      throw ProcessExit(ExitCode.usage.code);
    }

    if (!codeSigner.verify(
      message: hash,
      signature: signature,
      publicKeyPem: publicKeyPem,
    )) {
      logger.err(
        'Signature verification failed. The signature does not match '
        'the provided public key.',
      );
      throw ProcessExit(ExitCode.software.code);
    }

    return signature;
  }

  /// Diffs [patchArtifactPath] against [releaseArtifactPath] and describes
  /// the result as the [PatchArtifactBundle] for [arch].
  ///
  /// The hash (and its signature) is of the full patch artifact, not of the
  /// diff, since that is what the device has after applying the patch.
  ///
  /// If creating the diff fails, [progress] is failed with the error and the
  /// command exits with [ExitCode.software].
  Future<PatchArtifactBundle> createDiffBundle({
    required Arch arch,
    required String releaseArtifactPath,
    required String patchArtifactPath,
    required Progress progress,
    String? podfileLockHash,
  }) async {
    final hash = sha256
        .convert(await File(patchArtifactPath).readAsBytes())
        .toString();
    final hashSignature = await signHash(hash);

    final String diffPath;
    try {
      diffPath = await artifactManager.createDiff(
        releaseArtifactPath: releaseArtifactPath,
        patchArtifactPath: patchArtifactPath,
      );
    } on Exception catch (error) {
      progress.fail('$error');
      throw ProcessExit(ExitCode.software.code);
    }

    return PatchArtifactBundle(
      arch: arch.arch,
      path: diffPath,
      hash: hash,
      size: await File(diffPath).length(),
      hashSignature: hashSignature,
      podfileLockHash: podfileLockHash,
    );
  }

  /// The link percentage for the generated patch artifact if applicable.
  /// Returns `null` if the platform does not use a linker or if the linking
  /// step has not yet been run.
  double? get linkPercentage => null;

  /// The Dynamic Dispatch table cascade byte threshold to pass to the linker,
  /// from `--dd-max-bytes`.
  ///
  /// Unlike `Releaser.ddMaxBytes`, `0` is passed through rather than mapped
  /// to null: the linker reads `0` as "disable DD", while null leaves the
  /// linker on its own default.
  int? get ddMaxBytes {
    final value = argResults[CommonArguments.ddMaxBytesArg.name] as String?;
    return value == null ? null : int.tryParse(value);
  }

  /// The value of `--split-debug-info-path` if specified.
  String? get splitDebugInfoPath {
    return argResults.findOption(
      CommonArguments.splitDebugInfoArg.name,
      argParser: argParser,
    );
  }

  /// The path to the output file for the debug info.
  static File get debugInfoFile {
    return File(p.join(shorebirdEnv.buildDirectory.path, 'patch-debug.zip'));
  }

  /// Extracts the --build-name and --build-number from the --release-version
  /// argument if it's provided. Given `--release-version=1.2.3+4`, this will
  /// return `['--build-name=1.2.3', '--build-number=4']`, with the intent that
  /// these values will be forwarded to the `flutter build` command.
  ///
  /// Because not all platform types support both --build-name and
  /// --build-number, this needs to be handled in the platform-specific
  /// patchers instead of at the patch command level.
  ///
  /// We do this because some platforms encode the build version in their
  /// binaries (Android does this with .dex files). If a release and a patch
  /// have different version numbers, our [PatchDiffChecker] to warn the user of
  /// native changes, even though the user may not have actually changed any
  /// code or dependencies.
  ///
  /// Context: https://github.com/shorebirdtech/shorebird/issues/2270
  List<String> buildNameAndNumberArgsFromReleaseVersion(
    String? releaseVersion,
  ) {
    if (releaseVersion == null || !releaseVersion.contains('+')) {
      return [];
    }

    // If the user provided --build-name or --build-number before the --, we
    // don't want to override them.
    if (argResults.options.containsAnyOf([
      CommonArguments.buildNameArg.name,
      CommonArguments.buildNumberArg.name,
    ])) {
      return [];
    }

    // If the user provided --build-name or --build-number after the --, we
    // don't want to override them.
    if (argResults.rest.any(
      (a) =>
          a.startsWith('--${CommonArguments.buildNameArg.name}') ||
          a.startsWith('--${CommonArguments.buildNumberArg.name}'),
    )) {
      return [];
    }

    final parts = releaseVersion.split('+');
    return ['--build-name=${parts[0]}', '--build-number=${parts[1]}'];
  }
}
