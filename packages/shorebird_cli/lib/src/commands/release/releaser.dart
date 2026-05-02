import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/flutter_version_constraints.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

export 'package:pub_semver/pub_semver.dart';

/// {@template releaser}
/// Executes platform-specific functionality to create a release.
/// {@endtemplate}
abstract class Releaser {
  /// {@macro releaser}
  Releaser({
    required this.argResults,
    required this.flavor,
    required this.target,
  });

  /// The arguments passed to the command.
  final ArgResults argResults;

  /// The flavor of the release, if any. This is the --flavor argument passed to
  /// the release command.
  final String? flavor;

  /// The target script to run, if any. This is the --target argument passed to
  /// the release command.
  final String? target;

  /// The minimum Flutter version required to create a release of this type.
  Version? get minimumFlutterVersion => null;

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// The human-readable description of the release artifact being built (e.g.,
  /// "Android app", "iOS app").
  String get artifactDisplayName;

  /// Asserts that the command can be run.
  Future<void> assertPreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> assertArgsAreValid();

  /// Builds the release artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<FileSystemEntity> buildReleaseArtifacts();

  /// Uploads the release artifacts to the CodePush server.
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  });

  /// Creates a copy of [metadata] with releaser-specific fields updated.
  Future<UpdateReleaseMetadata> updatedReleaseMetadata(
    UpdateReleaseMetadata metadata,
  ) async {
    return metadata;
  }

  /// Instructions explaining next steps after running `shorebird release`. This
  /// could include how to upload the generated artifact to a store and how to
  /// patch the release.
  String get postReleaseInstructions;

  /// Extracts the release version from the compiled artifact.
  ///
  /// We extract the release version from the compiled artifact because we can
  /// be 100% certain that the artifact will report that same number when making
  /// patch check requests.
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  });

  /// Gets the base64-encoded public key from either file or command.
  ///
  /// Returns null if no public key is configured.
  Future<String?> getEncodedPublicKey() => argResults.getEncodedPublicKey();

  /// Whether the user is building with obfuscation. Checks for `--obfuscate`
  /// both as a parsed flag and after the `--` separator, since it can be
  /// passed either to Shorebird directly or forwarded to Flutter.
  bool get useObfuscation => argResults.flagPresent('obfuscate');

  /// Optional override for the DD table cascade byte threshold.
  ///
  /// Passed to Flutter tools via the SHOREBIRD_DD_MAX_BYTES environment
  /// variable for backwards compatibility: older Flutter builds that don't
  /// recognize the variable will silently ignore it, whereas an unknown
  /// command-line flag would cause a build failure.
  int? get ddMaxBytes {
    final value = argResults['dd-max-bytes'] as String?;
    final parsed = value != null ? int.tryParse(value) : 10000;
    // Return null if 0 (disabled) so the env var isn't set.
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  /// Path where the obfuscation map is saved during obfuscated builds.
  String get obfuscationMapPath => p.join(
    projectRoot.path,
    'build',
    'shorebird',
    'obfuscation_map.json',
  );

  /// Auto-adds --split-debug-info when --obfuscate is used without it.
  void addSplitDebugInfoDefault(List<String> buildArgs) {
    if (useObfuscation &&
        !buildArgs.any((a) => a.startsWith('--split-debug-info'))) {
      buildArgs.add(
        '--split-debug-info=${p.join('build', 'shorebird', 'symbols')}',
      );
    }
  }

  /// Adds obfuscation-related gen_snapshot options to [buildArgs].
  ///
  /// When obfuscation is enabled, passes --save-obfuscation-map to capture the
  /// mapping and --strip to remove unobfuscated DWARF debugging information
  /// from the compiled snapshot (the DWARF sections would otherwise leak
  /// identifiers that obfuscation was meant to hide).
  void addObfuscationMapArgs(List<String> buildArgs) {
    if (!useObfuscation) return;
    final mapDir = Directory(p.dirname(obfuscationMapPath));
    if (!mapDir.existsSync()) mapDir.createSync(recursive: true);
    buildArgs.addAll([
      '--extra-gen-snapshot-options=--save-obfuscation-map=$obfuscationMapPath',
      '--extra-gen-snapshot-options=--strip',
    ]);
  }

  /// Platform subdirectory for the supplement directory (e.g. 'android',
  /// 'ios'). Used to construct `build/<platformSubdir>/shorebird/`.
  String get supplementPlatformSubdir;

  /// Arch string for the supplement artifact on the server (e.g.
  /// 'android_supplement').
  String get supplementArtifactArch;

  /// Assembles the supplement directory: copies the obfuscation map (if
  /// present) into the platform supplement dir. Returns the directory, or null
  /// if empty.
  Directory? assembleSupplementDirectory() {
    final obfuscationMapFile = File(obfuscationMapPath);
    final hasObfuscationMap = useObfuscation && obfuscationMapFile.existsSync();
    final supplementDir = artifactManager.getReleaseSupplementDirectory(
      platformSubdir: supplementPlatformSubdir,
      create: hasObfuscationMap,
    );
    if (supplementDir == null) return null;

    final targetMapFile = File(
      p.join(supplementDir.path, 'obfuscation_map.json'),
    );
    if (hasObfuscationMap) {
      obfuscationMapFile.copySync(targetMapFile.path);
    } else if (targetMapFile.existsSync()) {
      // Remove stale obfuscation map from a previous obfuscated build so that
      // the supplement doesn't incorrectly signal that this release was
      // obfuscated.
      logger.detail(
        'Removing stale obfuscation map from supplement directory. '
        'If this release should be obfuscated, re-run with --obfuscate.',
      );
      targetMapFile.deleteSync();
    }

    // Return null if the supplement directory is now empty (nothing to upload).
    // Note: currently the obfuscation map is the only supplement artifact. If
    // other supplement files are added in the future, this check (and the
    // stale-file cleanup above) should be updated to handle them explicitly.
    if (supplementDir.listSync().isEmpty) return null;

    return supplementDir;
  }

  /// Uploads the supplement artifact (e.g. obfuscation map) if one was
  /// assembled. Call this at the end of [uploadReleaseArtifacts].
  ///
  // TODO(bdero): This is a separate network call from the primary artifact
  // upload, so an interruption between the two leaves the release without its
  // supplement. Now that the supplement drives patching decisions (e.g.
  // obfuscation), we should make this atomic or recoverable.
  // https://github.com/shorebirdtech/shorebird/issues/3630
  Future<void> uploadSupplementArtifact({
    required String appId,
    required int releaseId,
  }) async {
    final supplementDir = assembleSupplementDirectory();
    if (supplementDir != null) {
      await codePushClientWrapper.createSupplementReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        platform: releaseType.releasePlatform,
        supplementDirectoryPath: supplementDir.path,
        arch: supplementArtifactArch,
      );
    }
  }

  /// Asserts that the current Flutter version supports obfuscation, if
  /// obfuscation is enabled.
  Future<void> assertObfuscationIsSupported() async {
    if (!useObfuscation) return;
    final flutterVersion = await shorebirdFlutter.resolveFlutterVersion(
      shorebirdEnv.flutterRevision,
    );
    if (flutterVersion != null &&
        flutterVersion < minimumObfuscationFlutterVersion) {
      logger.err(
        'Obfuscation on ${releaseType.releasePlatform.displayName} '
        'requires Flutter $minimumObfuscationFlutterVersion or later '
        '(current: $flutterVersion).',
      );
      throw ProcessExit(ExitCode.unavailable.code);
    }
  }

  /// Verifies the obfuscation map was generated after build.
  void verifyObfuscationMap() {
    if (!useObfuscation) return;
    final mapFile = File(obfuscationMapPath);
    if (!mapFile.existsSync()) {
      logger.err(
        'Obfuscation was enabled but the obfuscation map was not '
        'generated at $obfuscationMapPath',
      );
      throw ProcessExit(ExitCode.software.code);
    }
    logger.detail('Obfuscation map saved to $obfuscationMapPath');
  }
}
