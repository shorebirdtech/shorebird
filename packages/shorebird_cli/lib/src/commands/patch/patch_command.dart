import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_session.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/extensions/version.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/patch_verification.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_chooser.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/split_debug_info.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Signature for a function that returns a [Patcher] for a given [ReleaseType].
typedef ResolvePatcher = Patcher Function(ReleaseType releaseType);

/// {@template patch_command}
/// A command that creates a shorebird patch for the provided target platforms.
/// `shorebird patch --platforms=android,ios`
/// {@endtemplate}
class PatchCommand extends ShorebirdCommand {
  /// {@macro patch_command}
  PatchCommand({ResolvePatcher? resolvePatcher}) {
    _resolvePatcher = resolvePatcher ?? getPatcher;
    argParser
      ..addMultiOption(
        CommonArguments.dartDefineArg.name,
        help: CommonArguments.dartDefineArg.description,
      )
      ..addMultiOption(
        CommonArguments.dartDefineFromFileArg.name,
        help: CommonArguments.dartDefineFromFileArg.description,
      )
      ..addMultiOption(
        'platforms',
        abbr: 'p',
        help: 'The platform(s) to build this patch for.',
        allowed: ReleaseType.values.map((e) => e.cliName).toList(),
      )
      ..addOption(
        CommonArguments.buildNameArg.name,
        help: CommonArguments.buildNameArg.description,
        defaultsTo: CommonArguments.buildNameArg.defaultValue,
      )
      ..addOption(
        CommonArguments.buildNumberArg.name,
        help: CommonArguments.buildNumberArg.description,
        defaultsTo: CommonArguments.buildNumberArg.defaultValue,
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: '''
The version of the associated release (e.g. "1.0.0").
If you are building an xcframework or aar, this number needs to match the host app's release version.
To target the latest release (e.g. the release that was most recently updated) use --release-version=latest.''',
      )
      ..addFlag(
        'allow-native-diffs',
        help: allowNativeDiffsHelpText,
        negatable: false,
      )
      ..addFlag(
        'allow-asset-diffs',
        help: allowAssetDiffsHelpText,
        negatable: false,
      )
      ..addFlag(
        'show-dex-diff',
        help: showDexDiffHelpText,
        negatable: false,
      )
      ..addOption(
        'track',
        aliases: const ['channel'],
        help: 'The track to publish the patch to.',
        defaultsTo: DeploymentTrack.stable.channel,
      )
      ..addFlag(
        'staging',
        negatable: false,
        help: '''
[DEPRECATED] Whether to publish the patch to the staging environment. Use --track=staging instead.''',
        hide: true,
      )
      ..addFlag(
        CommonArguments.noConfirmArg.name,
        help: CommonArguments.noConfirmArg.description,
        negatable: false,
        hide: true,
      )
      ..addOption(
        CommonArguments.exportOptionsPlistArg.name,
        help: CommonArguments.exportOptionsPlistArg.description,
      )
      ..addOption(
        CommonArguments.exportMethodArg.name,
        allowed: ExportMethod.values.map((e) => e.argName),
        help: CommonArguments.exportMethodArg.description,
        allowedHelp: {
          for (final method in ExportMethod.values)
            method.argName: method.description,
        },
      )
      ..addFlag(
        'codesign',
        help: 'Codesign the app bundle or XCFrameworks (iOS and macOS only).',
        defaultsTo: true,
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Validate but do not upload the patch.',
      )
      ..addOption(
        CommonArguments.privateKeyArg.name,
        help: CommonArguments.privateKeyArg.description,
      )
      ..addOption(
        CommonArguments.publicKeyArg.name,
        help: CommonArguments.publicKeyArg.description,
      )
      ..addOption(
        CommonArguments.publicKeyCmd.name,
        help: CommonArguments.publicKeyCmd.description,
      )
      ..addOption(
        CommonArguments.signCmd.name,
        help: CommonArguments.signCmd.description,
      )
      ..addOption(
        CommonArguments.splitDebugInfoArg.name,
        help: CommonArguments.splitDebugInfoArg.description,
      )
      ..addFlag(
        CommonArguments.obfuscateArg.name,
        help: CommonArguments.obfuscateArg.description,
        negatable: false,
        hide: true,
      )
      ..addOption(
        CommonArguments.minLinkPercentage.name,
        help: CommonArguments.minLinkPercentage.description,
        defaultsTo: CommonArguments.minLinkPercentage.defaultValue,
      )
      ..addOption(
        CommonArguments.ddMaxBytesArg.name,
        hide: true,
        help: CommonArguments.ddMaxBytesArg.description,
      );
  }

  /// Warning message for when native code diffs are detected.
  static final allowNativeDiffsHelpText = '''
Patch even if native code diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Native code changes cannot be included in a patch and attempting to do so can cause your app to crash or behave unexpectedly.''';

  /// Help text for the full DEX diff flag.
  static const showDexDiffHelpText = '''
Print every differing instruction when native changes are detected in an Android patch.
Without this, the first few differing instructions of the first ten changed methods are shown, string constants are replaced by their length, and a payload such as a switch table or an array initializer is cut after its first few units. Output contains your app's bytecode, including class and method names, and is written to the shorebird.log file support asks you to attach.''';

  /// Warning message for when asset diffs are detected.
  static final allowAssetDiffsHelpText = '''
Patch even if asset diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Asset changes cannot be included in a patch can cause your app to behave unexpectedly.''';

  late final ResolvePatcher _resolvePatcher;

  @override
  String get description =>
      'Creates a shorebird patch for the provided target platforms.';

  @override
  String get name => 'patch';

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The build flavor, if provided.
  late String? flavor = results.findOption('flavor', argParser: argParser);

  /// The target script, if provided.
  late final String? target = resolveTarget();

  /// Whether to allow changes in assets (--allow-asset-diffs).
  bool get allowAssetDiffs => results['allow-asset-diffs'] == true;

  /// Whether to allow changes in native code (--allow-native-diffs).
  bool get allowNativeDiffs => results['allow-native-diffs'] == true;

  /// Whether the patch is targeting the latest release version
  /// (--release-version=latest).
  bool get useLatestRelease => results['release-version'] == 'latest';

  /// The deployment track to publish the patch to.
  DeploymentTrack get track => DeploymentTrack(results['track'] as String);

  @override
  Future<int> run() async {
    final releaseTypes = releaseTypesOrUsageError(siblingCommand: 'patches');

    final ddMaxBytes = results[CommonArguments.ddMaxBytesArg.name] as String?;
    if (ddMaxBytes != null && (int.tryParse(ddMaxBytes) ?? -1) < 0) {
      usageException(
        '--${CommonArguments.ddMaxBytesArg.name} must be a non-negative '
        'integer (got $ddMaxBytes).',
      );
    }

    if (results.wasParsed('staging')) {
      logger.err(
        '''The --staging flag is deprecated and will be removed in a future release. Use --track=staging instead.''',
      );
      return ExitCode.usage.code;
    }

    final published = <PublishedPatch>[];
    for (final releaseType in releaseTypes) {
      published.add(await createPatch(_resolvePatcher(releaseType)));
    }

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'track': track.channel,
        'patches': [for (final p in published) p.toJson()],
      });
    }

    return ExitCode.success.code;
  }

  /// Returns a [Patcher] for the given [ReleaseType].
  @visibleForTesting
  Patcher getPatcher(ReleaseType releaseType) {
    switch (releaseType) {
      case ReleaseType.aar:
        return AarPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.android:
        return AndroidPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.ios:
        return IosPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.iosFramework:
        return IosFrameworkPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.linux:
        return LinuxPatcher(
          argParser: argParser,
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.macos:
        return MacosPatcher(
          argParser: argParser,
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.windows:
        return WindowsPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
    }
  }

  /// The last built Flutter revision.
  String? lastBuiltFlutterRevision;

  /// Creates a patch using the provided [patcher].
  ///
  /// Returns what was published. A dry run does not return: it exits the
  /// process with success once the patch has been checked.
  @visibleForTesting
  Future<PublishedPatch> createPatch(Patcher patcher) async {
    await _assertCanPatch(patcher);

    await cache.updateAll();

    final app = await codePushClientWrapper.getApp(appId: appId);

    final resolved = await _resolveRelease(patcher);
    final release = resolved.release;

    assertReleaseContainsPlatform(release: release, patcher: patcher);
    assertReleaseIsActive(release: release, patcher: patcher);
    _warnIfFlutterRevisionHasKnownIssue(release: release, patcher: patcher);

    try {
      await shorebirdFlutter.installRevision(revision: release.flutterRevision);
    } on Exception {
      throw ProcessExit(ExitCode.software.code);
    }

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: release.flutterRevision,
    );

    // Fail before downloading anything if the release's Flutter is too old.
    await runScoped(
      () async {
        await _assertReleaseFlutterVersionSupported(
          patcher: patcher,
          release: release,
        );
        await _warnIfInstallOnlySkipsSignatureCheck(release: release);
      },
      values: {shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv)},
    );

    await patcher.prepareForRelease(appId: appId, release: release);
    final downloaded = await _downloadReleaseArtifacts(
      patcher: patcher,
      release: release,
    );
    _configureSigning(
      patcher: patcher,
      release: release,
      releaseArtifact: downloaded.releaseArtifact,
    );

    // The extracted supplement (including any obfuscation map the build loads)
    // is needed until the patch is built and published.
    try {
      await _configureObfuscation(
        patcher: patcher,
        release: release,
        obfuscationMapFile: downloaded.obfuscationMapFile,
      );

      return await runScoped(
        () => _buildAndPublishPatch(
          patcher: patcher,
          app: app,
          release: release,
          existingPatchArtifact: resolved.patchArtifactFile,
          inferredReleaseVersion: resolved.inferredReleaseVersion,
          releaseArtifact: downloaded.releaseArtifact,
          releaseArchive: downloaded.releaseArchive,
          supplementDirectory: downloaded.supplementDirectory,
        ),
        values: {
          shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
        },
      );
    } finally {
      if (downloaded.supplementDirectory case final directory?) {
        directory.deleteTemporarySync();
      }
    }
  }

  /// Checks that [patcher] can build a patch with the given arguments and
  /// flavors, exiting otherwise.
  Future<void> _assertCanPatch(Patcher patcher) async {
    await patcher.assertPreconditions();
    await patcher.assertArgsAreValid();
    assertSigningArgsValid();

    // A new track is created on first publish, so reject a name that
    // `channels create` and `patches set-track` would also reject.
    final trackNameError = CommonArguments.nameError(
      label: 'Track name',
      value: results['track'] as String,
      maxLength: CommonArguments.trackNameMaxLength,
    );
    if (trackNameError != null) usageException(trackNameError);

    try {
      await shorebirdValidator.validateFlavors(
        flavorArg: flavor,
        releasePlatform: patcher.releaseType.releasePlatform,
      );
    } on ValidationFailedException catch (e) {
      throw PreconditionFailedExit(e);
    }
  }

  /// Determines which release to patch.
  ///
  /// When the release version can't be determined any other way, the patch
  /// is built first to read the version from it, so the built artifact is
  /// returned as well.
  Future<
    ({Release release, File? patchArtifactFile, bool inferredReleaseVersion})
  >
  _resolveRelease(Patcher patcher) async {
    var inferredReleaseVersion = false;
    File? patchArtifactFile;
    final Release release;
    final releasePlatform = patcher.releaseType.releasePlatform;
    if (useLatestRelease) {
      final releases = await codePushClientWrapper.getReleases(appId: appId);
      releases
        ..removeWhere(
          (release) => !release.hasPlatform(releasePlatform),
        )
        ..sortByUpdatedAt();
      if (releases.isEmpty) {
        throw _noReleasesToPatch(patcher.releaseType);
      }
      // Use the most recently updated release for the specified platform.
      release = releases.last;
    } else if (results.wasParsed('release-version')) {
      final releaseVersion = results['release-version'] as String;
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    } else if (shorebirdEnv.canAcceptUserInput) {
      release = await promptForRelease(patcher.releaseType);
    } else {
      // Without a terminal to prompt in, the release version is guessed by
      // building and reading it back out of the artifact, which some release
      // types can't do.
      if (patcher.requiresReleaseVersionArg) {
        usageException(
          'Missing required argument: --release-version. The release version '
          "can't be determined from a ${patcher.releaseType.cliName} build, "
          'so pass --release-version=<version> (or --release-version=latest) '
          'when running non-interactively.',
        );
      }
      final flutterVersionString = await shorebirdFlutter
          .getVersionAndRevision();
      logger.warn('''
The release version to patch was not specified.
Building with Flutter $flutterVersionString to determine the release version...
+-------------------------------------------------------------------------------+
| Specify a release version (e.g. --release-version=1.0.0+1)                    |
| to avoid a speculative build with the latest Flutter version.                 |
| Tip: Use --release-version=latest to target the most recent release.          |
+-------------------------------------------------------------------------------+
''');
      lastBuiltFlutterRevision = shorebirdEnv.flutterRevision;
      inferredReleaseVersion = true;
      patchArtifactFile = await _tryBuildingArtifact<File>(
        patcher.buildPatchArtifact,
      );
      final releaseVersion = await patcher.extractReleaseVersionFromArtifact(
        patchArtifactFile,
      );
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    }

    return (
      release: release,
      patchArtifactFile: patchArtifactFile,
      inferredReleaseVersion: inferredReleaseVersion,
    );
  }

  /// Downloads [release]'s primary artifact and, if the platform has one, its
  /// supplement, which is extracted. Detects whether the release was built
  /// with obfuscation from the supplement's obfuscation map.
  Future<
    ({
      ReleaseArtifact releaseArtifact,
      File releaseArchive,
      Directory? supplementDirectory,
      File? obfuscationMapFile,
    })
  >
  _downloadReleaseArtifacts({
    required Patcher patcher,
    required Release release,
  }) async {
    final releasePlatform = patcher.releaseType.releasePlatform;
    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: patcher.primaryReleaseArtifactArch,
      platform: releasePlatform,
    );

    final supplementalArtifact =
        patcher.supplementaryReleaseArtifactArch != null
        ? await codePushClientWrapper.maybeGetReleaseArtifact(
            appId: appId,
            releaseId: release.id,
            arch: patcher.supplementaryReleaseArtifactArch!,
            platform: releasePlatform,
          )
        : null;

    final releaseArchive = await downloadReleaseArtifact(
      releaseArtifact: releaseArtifact,
    );

    final supplementArchive = supplementalArtifact != null
        ? await downloadReleaseArtifact(releaseArtifact: supplementalArtifact)
        : null;

    // Download and extract the supplement archive (if present).
    Directory? supplementDirectory;
    File? obfuscationMapFile;
    if (supplementArchive != null) {
      supplementDirectory = Directory.systemTemp.createTempSync();
      await artifactManager.extractZip(
        zipFile: supplementArchive,
        outputDirectory: supplementDirectory,
      );
      final candidateMapFile = File(
        p.join(supplementDirectory.path, 'obfuscation_map.json'),
      );
      if (candidateMapFile.existsSync()) {
        obfuscationMapFile = candidateMapFile;
        logger.info(
          'Release was built with obfuscation. '
          'Applying obfuscation map to patch build.',
        );
      }
    }

    return (
      releaseArtifact: releaseArtifact,
      releaseArchive: releaseArchive,
      supplementDirectory: supplementDirectory,
      obfuscationMapFile: obfuscationMapFile,
    );
  }

  /// Configures [patcher] to build the patch against the key [release]'s
  /// [releaseArtifact] embeds.
  ///
  /// Shorebird signs the patches of a release that embeds a managed key, so
  /// passing a key of your own for one is a usage error.
  void _configureSigning({
    required Patcher patcher,
    required Release release,
    required ReleaseArtifact releaseArtifact,
  }) {
    final signing = releaseArtifact.signing;
    if (signing?.mode != ReleaseSigningMode.managed.value) return;

    final keyArgs = [
      CommonArguments.publicKeyArg.name,
      CommonArguments.publicKeyCmd.name,
      CommonArguments.privateKeyArg.name,
      CommonArguments.signCmd.name,
    ].where(results.wasParsed);
    if (keyArgs.isNotEmpty) {
      usageException(
        'Release ${release.version} is signed with a Shorebird-managed key, '
        'and Shorebird signs its patches. Remove '
        '${keyArgs.map((arg) => '--$arg').join(', ')}.',
      );
    }
    final publicKeyPem = signing!.publicKeyPem;
    if (publicKeyPem == null) {
      logger.err(
        'Release ${release.version} is signed with a Shorebird-managed key, '
        'but the server did not return it. Try again, and contact Shorebird '
        'support if this persists.',
      );
      throw ProcessExit(ExitCode.software.code);
    }
    patcher.releaseManagedPublicKeyPem = publicKeyPem;

    // A patch built to read the release version embedded no key, so it
    // can't be compared with this release: build it again with the key.
    lastBuiltFlutterRevision = null;
  }

  /// Configures [patcher] to build the patch with the same obfuscation as
  /// [release], which has [obfuscationMapFile] if it was obfuscated, and sets
  /// the extra Flutter build args that requires.
  Future<void> _configureObfuscation({
    required Patcher patcher,
    required Release release,
    required File? obfuscationMapFile,
  }) async {
    final releasePlatform = patcher.releaseType.releasePlatform;

    // If the user explicitly passed --obfuscate but the release has no
    // obfuscation map, the patch would be obfuscated against a non-obfuscated
    // release, producing a broken patch.
    final userPassedObfuscate = results.flagPresent('obfuscate');
    if (userPassedObfuscate && obfuscationMapFile == null) {
      usageException(
        '--obfuscate was passed, but release ${release.version} was not '
        'built with obfuscation. A patch cannot change the obfuscation mode '
        'of a release: re-run without --obfuscate to patch this release, or '
        'create a new release with --obfuscate.',
      );
    }
    if (userPassedObfuscate && obfuscationMapFile != null) {
      logger.info(
        '--obfuscate is not needed for patching. Obfuscation is applied '
        'automatically when the release was built with --obfuscate.',
      );
    }

    // Building a patch with the release's obfuscated names needs
    // gen_snapshot's --load-obfuscation-map, which older Flutter versions
    // lack. Only patches that are linked against the release need matching
    // names; elsewhere the patch is obfuscated independently instead.
    var loadObfuscationMap = obfuscationMapFile != null;
    final releaseFlutterVersion = tryParseVersion(release.flutterVersion ?? '');
    if (loadObfuscationMap &&
        releaseFlutterVersion != null &&
        releaseFlutterVersion < minimumObfuscationFlutterVersion) {
      if (patchesLinkAgainstRelease(releasePlatform)) {
        logger.err(
          'Release ${release.version} was built with obfuscation on Flutter '
          '$releaseFlutterVersion, but patching an obfuscated '
          '${releasePlatform.displayName} release requires Flutter '
          '$minimumObfuscationFlutterVersion or later.',
        );
        throw ProcessExit(ExitCode.unavailable.code);
      }
      loadObfuscationMap = false;
    }

    patcher
      ..obfuscate = obfuscationMapFile != null
      ..obfuscationMapPath = loadObfuscationMap
          ? obfuscationMapFile!.path
          : null;

    // Build extra args to inject into the Flutter build command. These use
    // --extra-gen-snapshot-options= because they're passed through Flutter's
    // build system, which forwards them to gen_snapshot. This is distinct from
    // patcher.obfuscationGenSnapshotArgs, which produces bare gen_snapshot
    // flags (e.g. --load-obfuscation-map=...) for direct gen_snapshot/linker
    // calls made by Apple patchers outside the Flutter build.
    final extraBuildArgs = <String>[];
    if (obfuscationMapFile != null) {
      extraBuildArgs.add('--obfuscate');
      if (loadObfuscationMap) {
        final loadMapOption =
            '--load-obfuscation-map=${obfuscationMapFile.path}';
        extraBuildArgs.add('--extra-gen-snapshot-options=$loadMapOption');
      }

      // Gate --strip on the release's Flutter revision (not the user's
      // currently-installed pin) so the patch's gen_snapshot behavior
      // matches the release's. On Android with Flutter 3.44+ AGP performs
      // the strip; passing --strip here would pre-strip the snapshot,
      // leaving AGP nothing to strip and tripping flutter_tools'
      // post-build "libapp.so.sym or libapp.so.dbg not present" check.
      final shouldPreStripInGenSnapshot = await shorebirdFlutter
          .shouldPreStripLibappInGenSnapshot(
            platform: patcher.releaseType.releasePlatform,
            flutterRevision: release.flutterRevision,
          );

      if (shouldPreStripInGenSnapshot) {
        // Strip unobfuscated DWARF debug info from the compiled snapshot
        // so it doesn't leak identifiers that obfuscation was meant to
        // hide. On Android 3.44+ this is handled by AGP instead; see the
        // block above.
        extraBuildArgs.add('--extra-gen-snapshot-options=--strip');
      }
    }
    // --obfuscate may come from the user or from the obfuscation map
    // injection above; either way it needs --split-debug-info, as on release.
    final splitDebugInfo = splitDebugInfoDefault(
      obfuscate:
          results.flagPresent('obfuscate') ||
          extraBuildArgs.contains('--obfuscate'),
      hasSplitDebugInfo: results.optionPresent('split-debug-info'),
    );
    if (splitDebugInfo != null) extraBuildArgs.add(splitDebugInfo);
    patcher.extraBuildArgs = extraBuildArgs;
  }

  /// Builds the patch with [release]'s Flutter revision (unless
  /// [existingPatchArtifact] was already built with it), checks it against the
  /// release, and uploads it. Must run with the release's Flutter revision in
  /// scope.
  ///
  /// A dry run exits the process with success once the patch is checked.
  Future<PublishedPatch> _buildAndPublishPatch({
    required Patcher patcher,
    required AppMetadata app,
    required Release release,
    required File? existingPatchArtifact,
    required bool inferredReleaseVersion,
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required Directory? supplementDirectory,
  }) async {
    var patchArtifactFile = existingPatchArtifact;
    await cache.updateAll();

    // Set up build tracing before any flutter build / aot_tools /
    // gen_snapshot call runs. Version-gated inside prepareBuildTrace —
    // a no-op on older Flutter pins. Summary is written at the very
    // end of createPatch, after aot_tools link and artifact uploads.
    await artifactBuilder.prepareBuildTrace(
      platform: patcher.releaseType.releasePlatform.name,
    );

    // Don't built the patch artifact twice with the same Flutter revision.
    if (lastBuiltFlutterRevision != release.flutterRevision) {
      final flutterVersionString = await shorebirdFlutter
          .getVersionAndRevision();
      logger.info('''
Building patch with Flutter $flutterVersionString
''');
      patchArtifactFile = await _tryBuildingArtifact<File>(
        () => patcher.buildPatchArtifact(
          releaseVersion: release.version,
        ),
      );
    }

    final diffStatus = await assertUnpatchableDiffs(
      releaseArtifact: releaseArtifact,
      releaseArchive: releaseArchive,
      patchArchive: patchArtifactFile!,
      patcher: patcher,
    );
    final patchArtifactBundles = await patcher.createPatchArtifacts(
      appId: appId,
      releaseId: release.id,
      releaseArtifact: releaseArchive,
      supplementDirectory: supplementDirectory,
    );

    _exitIfDryRun(patcher: patcher, release: release);

    await logPatchSummary(
      app: app,
      releaseVersion: release.version,
      patcher: patcher,
      patchArtifactBundles: patchArtifactBundles,
    );

    // Write the build-trace summary after all compile/link work has
    // finished — the metadata upload is the last step and it carries
    // this summary, so we finalize immediately before it. No-op when
    // tracing wasn't set up (older Flutter pin).
    artifactBuilder.writeBuildTraceSummary();

    final metadata = await _createPatchMetadata(
      patcher: patcher,
      diffStatus: diffStatus,
      inferredReleaseVersion: inferredReleaseVersion,
    );

    final patch = await patcher.uploadPatchArtifacts(
      appId: appId,
      releaseId: release.id,
      metadata: metadata.toJson(),
      track: track,
      artifacts: patchArtifactBundles,
    );

    return PublishedPatch(
      platform: patcher.releaseType.releasePlatform,
      release: release,
      patch: patch,
      linkPercentage: patcher.linkPercentage,
    );
  }

  /// Exits if [release] was built with a Flutter version older than
  /// [Patcher.minimumFlutterVersion]. Must run with the release's Flutter
  /// revision in scope. A version that can't be determined is let through.
  Future<void> _assertReleaseFlutterVersionSupported({
    required Patcher patcher,
    required Release release,
  }) async {
    final minimumFlutterVersion = patcher.minimumFlutterVersion;
    if (minimumFlutterVersion == null) return;

    final flutterVersion = await shorebirdFlutter.getVersion();
    if (flutterVersion == null || flutterVersion >= minimumFlutterVersion) {
      return;
    }

    final flutterVersionAndRevision = await shorebirdFlutter
        .getVersionAndRevision();
    logger.err('''
Release ${release.version} was built with Flutter $flutterVersionAndRevision, but at least Flutter $minimumFlutterVersion is required to patch with `${patcher.releaseType.cliName}`.
A release cannot change Flutter versions, so create a new release with ${lightCyan.wrap('shorebird release ${patcher.releaseType.cliName} --flutter-version=${minimumReleaseFlutterVersion(patcher.releaseType)}')} and patch that one.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''');
    throw ProcessExit(ExitCode.software.code);
  }

  /// Warns if shorebird.yaml asks for `patch_verification: install_only` and
  /// [release] was built with a Flutter whose updater never checks patch
  /// signatures in that mode (since updater#352), so devices on [release]
  /// install this patch without checking its signature. Only a new release
  /// can change that, so the patch goes ahead. Must run with the release's
  /// Flutter revision in scope.
  ///
  /// Reads today's shorebird.yaml, which is the release's unless it has
  /// changed since.
  Future<void> _warnIfInstallOnlySkipsSignatureCheck({
    required Release release,
  }) async {
    final patchVerification = shorebirdEnv
        .getShorebirdYaml()
        ?.patchVerification;
    if (patchVerification != PatchVerification.installOnly) return;
    if (!installOnlySkipsSignatureCheck(shorebirdEnv.shorebirdEngineRevision)) {
      return;
    }
    final flutterVersion = await shorebirdFlutter.getVersionAndRevision();
    logger.warn(
      '''
shorebird.yaml sets `patch_verification: install_only`, which does not check patch signatures with Flutter $flutterVersion, the Flutter release ${release.version} was built with. If the release was built with this setting, devices on it will install this patch without checking its signature.
To have signatures checked, remove `patch_verification` from shorebird.yaml (or set it to `strict`) and create a new release, or release with a Flutter version that checks signatures in install_only mode, such as --flutter-version=3.41.8.''',
    );
  }

  /// Warns if Shorebird marked the Flutter revision [release] was built with
  /// as having a known problem on [patcher]'s platform. A patch can't change
  /// the Flutter a release was built with, so the patch goes ahead; the fix
  /// is a new release.
  void _warnIfFlutterRevisionHasKnownIssue({
    required Release release,
    required Patcher patcher,
  }) {
    final issue = release.flutterRevisionIssue;
    if (issue == null) return;
    final platform = patcher.releaseType.releasePlatform;
    final platforms = issue.platforms;
    if (platforms != null && !platforms.contains(platform)) return;

    String flutterBuild(String? version, String revision) {
      final shortRevision = revision.length > 10
          ? revision.substring(0, 10)
          : revision;
      return version == null
          ? 'Flutter revision $shortRevision'
          : 'Flutter $version ($shortRevision)';
    }

    final details = issue.details;
    final fixedInRevision = issue.fixedInRevision;
    final releaseWith = fixedInRevision == null
        ? 'a Flutter version without this problem'
        : '${flutterBuild(issue.fixedInVersion, fixedInRevision)} or newer';
    final builtWith = flutterBuild(
      release.flutterVersion,
      release.flutterRevision,
    );
    final problem =
        'Release ${release.version} was built with $builtWith, which has a '
        'known problem on ${platform.displayName}: ${issue.summary}';
    final fix =
        'A patch cannot change the Flutter version a release was built with. '
        'To fix this, create a new release with $releaseWith.';
    logger.warn([problem, ?details, fix].join('\n'));
  }

  /// Reports a successful check and exits with success if this is a dry run.
  void _exitIfDryRun({required Patcher patcher, required Release release}) {
    final dryRun = results['dry-run'] == true;
    if (!dryRun) return;

    if (isJsonMode) {
      emitJsonSuccess({
        'dry_run': true,
        'app_id': appId,
        'platform': patcher.releaseType.releasePlatform.name,
        'release_id': release.id,
        'release_version': release.version,
        'link_percentage': patcher.linkPercentage,
      });
    } else {
      logger
        ..info('No issues detected.')
        ..info('The server may enforce additional checks.');
    }
    throw ProcessExit(ExitCode.success.code);
  }

  /// The metadata uploaded with the patch.
  Future<CreatePatchMetadata> _createPatchMetadata({
    required Patcher patcher,
    required DiffStatus diffStatus,
    required bool inferredReleaseVersion,
  }) {
    final baseMetadata = CreatePatchMetadata(
      releasePlatform: patcher.releaseType.releasePlatform,
      usedIgnoreAssetChangesFlag: allowAssetDiffs,
      hasAssetChanges: diffStatus.hasAssetChanges,
      usedIgnoreNativeChangesFlag: allowNativeDiffs,
      hasNativeChanges: diffStatus.hasNativeChanges,
      inferredReleaseVersion: inferredReleaseVersion,
      isSigned:
          results.wasParsed(CommonArguments.privateKeyArg.name) ||
          results.wasParsed(CommonArguments.signCmd.name),
      environment: BuildEnvironmentMetadata(
        flutterRevision: shorebirdEnv.flutterRevision,
        operatingSystem: platform.operatingSystem,
        operatingSystemVersion: platform.operatingSystemVersion,
        shorebirdVersion: packageVersion,
        shorebirdYaml: shorebirdEnv.getShorebirdYaml()!,
        usesShorebirdCodePushPackage: shorebirdEnv.usesShorebirdCodePushPackage,
      ),
      // Attach the build-trace summary if the build produced one.
      // Null for older Flutter pins without the --shorebird-trace
      // flag or when trace parsing failed; uploader sends
      // null-as-omitted.
      buildTraceSummary: buildTraceSession.summary?.toJson(),
    );
    return patcher.updatedCreatePatchMetadata(baseMetadata);
  }

  /// Prompts the user for the specific release to patch.
  Future<Release> promptForRelease(ReleaseType releaseType) async {
    final platform = releaseType.releasePlatform;
    final releases = await codePushClientWrapper.getReleases(appId: appId);

    final releasesForPlatform = releases.where(
      (release) => release.hasPlatform(platform),
    );

    if (releasesForPlatform.isEmpty) {
      throw _noReleasesToPatch(releaseType);
    }

    return chooseRelease(
      releases: releasesForPlatform,
      action: 'patch',
    );
  }

  /// Logs that there is nothing to patch for [releaseType] and returns the
  /// [ProcessExit] to throw.
  ProcessExit _noReleasesToPatch(ReleaseType releaseType) {
    logger
      ..err(
        '''No ${releaseType.releasePlatform.displayName} releases found for app $appId.''',
      )
      ..info(
        '''A patch needs a release to apply to. Create one with ${lightCyan.wrap('shorebird release ${releaseType.cliName}')}, or pass --app-id / --flavor if this is the wrong app.''',
      );
    return ProcessExit(ExitCode.usage.code);
  }

  /// Asserts that the release contains a platform for the given [patcher].
  void assertReleaseContainsPlatform({
    required Release release,
    required Patcher patcher,
  }) {
    final releasePlatform = patcher.releaseType.releasePlatform;
    if (!release.hasPlatform(releasePlatform)) {
      final platformName = releasePlatform.name;
      logger.err(
        '''No release exists for $platformName in release version ${release.version}. Please run shorebird release $platformName to create one.''',
      );
      throw ProcessExit(ExitCode.software.code);
    }
  }

  /// Asserts that the provided [release] is active.
  void assertReleaseIsActive({
    required Release release,
    required Patcher patcher,
  }) {
    if (!release.isActiveOn(patcher.releaseType.releasePlatform)) {
      logger.err('''
Release ${release.version} is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.''');
      throw ProcessExit(ExitCode.software.code);
    }
  }

  /// Ensures the diff between the release and patch archives is safe to patch.
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File patchArchive,
    required File releaseArchive,
    required Patcher patcher,
  }) async {
    try {
      // Must be awaited inside the try, otherwise the catch clauses below never
      // see the failure and the patch exits with an unhandled exception.
      return await patcher.assertUnpatchableDiffs(
        releaseArtifact: releaseArtifact,
        releaseArchive: releaseArchive,
        patchArchive: patchArchive,
      );
    } on UserCancelledException {
      logger.err('Aborting.');
      throw PromptDeclinedExit();
    } on UnpatchableChangeException {
      // The diff checker has already named the change and the flag that
      // overrides it.
      logger.info('Not publishing.');
      throw ProcessExit(ExitCode.software.code);
    }
  }

  /// Logs a summary of the patch to be created, including:
  /// - The app name and ID
  /// - The release version
  /// - The platform
  /// - The track
  /// - The link percentage (if iOS)
  /// - The debug info file (if iOS)
  Future<void> logPatchSummary({
    required AppMetadata app,
    required String releaseVersion,
    required Patcher patcher,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final archMetadata = patchArtifactBundles.keys.map((arch) {
      final size = formatBytes(patchArtifactBundles[arch]!.size);
      return '${arch.name} ($size)';
    });
    final trackSummary = (() {
      return switch (track) {
        DeploymentTrack.staging => '🟠 Track: ${lightCyan.wrap('Staging')}',
        DeploymentTrack.beta => '🔵 Track: ${lightCyan.wrap('Beta')}',
        DeploymentTrack.stable => '🟢 Track: ${lightCyan.wrap('Stable')}',
        final String trackName => '⚪️ Track: ${lightCyan.wrap(trackName)}',
      };
    })();

    final linkPercentage = patcher.linkPercentage;
    final minLinkPercentageRaw =
        results[CommonArguments.minLinkPercentage.name] as String;
    final minLinkPercentage = int.tryParse(minLinkPercentageRaw);
    if (minLinkPercentage == null ||
        minLinkPercentage < CommonArguments.minLinkPercentageMin ||
        minLinkPercentage > CommonArguments.minLinkPercentageMax) {
      usageException(
        '--min-link-percentage must be an integer between '
        '${CommonArguments.minLinkPercentageMin} and '
        '${CommonArguments.minLinkPercentageMax} '
        '(got $minLinkPercentageRaw).',
      );
    }
    if (linkPercentage != null && linkPercentage < minLinkPercentage) {
      logger
        ..err(
          '''The link percentage of this patch ($linkPercentage%) is below the minimum threshold ($minLinkPercentage%).''',
        )
        ..info(
          '''Not publishing. Lower --min-link-percentage to accept this patch, or see ${Patcher.debugInfoFile.path} for what could not be linked.''',
        );
      throw ProcessExit(ExitCode.software.code);
    }

    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.displayName)} ${lightCyan.wrap('[${archMetadata.join(', ')}]')}''',
      trackSummary,
      if (linkPercentage != null &&
          linkPercentage < Patcher.linkPercentageWarningThreshold)
        '''🔍 Debug Info: ${lightCyan.wrap(Patcher.debugInfoFile.path)}''',
    ];

    logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''');
  }

  /// Downloads the given [releaseArtifact].
  Future<File> downloadReleaseArtifact({
    required ReleaseArtifact releaseArtifact,
  }) async {
    final File artifactFile;
    try {
      artifactFile = await artifactManager.downloadReleaseArtifact(
        releaseArtifact,
        message: 'Downloading ${releaseArtifact.arch}',
      );
    } on Exception {
      throw ProcessExit(ExitCode.software.code);
    }

    return artifactFile;
  }
}

/// Executes [build] to build the artifact and includes
/// special handling thrown exceptions such as [ArtifactBuildException].
Future<R> _tryBuildingArtifact<R>(Future<R> Function() build) async {
  try {
    return await build();
  } on ArtifactBuildException catch (e) {
    logger.err(e.message);
    if (!e.fixRecommendation.isNullOrEmpty) {
      logger.info(e.fixRecommendation);
    }
    throw ProcessExit(ExitCode.software.code);
  } on Exception catch (e) {
    logger.err('Failed to build patch artifacts: $e');
    throw ProcessExit(ExitCode.software.code);
  }
}

/// Extension on list of releases for sorting the releases.
extension SortReleases on List<Release> {
  /// Sort the list of releases by when they were last updated ascending.
  void sortByUpdatedAt() => sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
}

/// {@template published_patch}
/// One platform's outcome of `shorebird patch`: which release it patched,
/// the patch that resulted, and how much of the release's Dart code the
/// patch could share with it.
/// {@endtemplate}
class PublishedPatch {
  /// {@macro published_patch}
  const PublishedPatch({
    required this.platform,
    required this.release,
    required this.patch,
    required this.linkPercentage,
  });

  /// The platform the patch was built for.
  final ReleasePlatform platform;

  /// The release the patch applies to.
  final Release release;

  /// The patch as the server created it.
  final CreatePatchResponse patch;

  /// The share of Dart code linked against the release, as a percentage,
  /// where the platform reports one.
  final double? linkPercentage;

  /// The shape written into the `--json` envelope.
  Map<String, dynamic> toJson() => {
    'platform': platform.name,
    'release_id': release.id,
    'release_version': release.version,
    'patch_id': patch.id,
    'patch_number': patch.number,
    'link_percentage': linkPercentage,
  };
}
