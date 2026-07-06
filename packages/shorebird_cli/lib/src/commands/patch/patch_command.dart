import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:meta/meta.dart';
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
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_chooser.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:uuid/uuid.dart';

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
      ..addOption(
        'track',
        help: 'The track to publish the patch to.',
        defaultsTo: DeploymentTrack.stable.channel,
      )
      ..addOption(
        'patch-id',
        help: '''
A stable correlation key (e.g. a git SHA) used to unify a logical patch
across platforms. When two invocations on the same release supply the same
--patch-id, the server returns the existing patch instead of allocating a
new number — the iOS and Android halves of the same change end up sharing
one patch number visible to end users.

When omitted, the CLI defaults to the current git commit SHA on CI or when
the working tree is clean, so separate platform builds of the same commit
group automatically. On a dirty local tree (uncommitted changes) no
cross-invocation grouping happens; the platforms within a single
multi-platform invocation still share a one-time key.''',
      )
      ..addFlag(
        'staging',
        negatable: false,
        help: '''
[DEPRECATED] Whether to publish the patch to the staging environment. Use --track=staging instead.''',
        hide: true,
      )
      // Added for https://github.com/shorebirdtech/shorebird/issues/3223.
      // Can be removed fall 2026 or later.
      ..addFlag(
        'confirm',
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
        help: 'Codesign the application bundle (iOS only).',
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
      );
  }

  /// Warning message for when native code diffs are detected.
  static final allowNativeDiffsHelpText = '''
Patch even if native code diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Native code changes cannot be included in a patch and attempting to do so can cause your app to crash or behave unexpectedly.''';

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
  late String? target = results.findOption('target', argParser: argParser);

  /// Whether to prompt for confirmation before creating the patch.
  bool get confirm => results['confirm'] == true;

  /// Whether to allow changes in assets (--allow-asset-diffs).
  bool get allowAssetDiffs => results['allow-asset-diffs'] == true;

  /// Whether to allow changes in native code (--allow-native-diffs).
  bool get allowNativeDiffs => results['allow-native-diffs'] == true;

  /// Whether the patch is for the staging environment.
  bool get isStaging => track == DeploymentTrack.staging;

  /// Whether the patch is targeting the latest release version
  /// (--release-version=latest).
  bool get useLatestRelease => results['release-version'] == 'latest';

  /// The deployment track to publish the patch to.
  DeploymentTrack get track => DeploymentTrack(results['track'] as String);

  /// The commit SHA of `HEAD`, resolved once per invocation and null when the
  /// patch is not being cut inside a git checkout. Populated by [run] before
  /// the per-platform fan-out. Recorded on every patch for provenance (see
  /// [gitShaForProvenance]) and used as the default correlation key when it
  /// identifies the code being shipped (see [_resolveClientPatchId]).
  String? _gitSha;

  /// Whether the working tree has uncommitted changes. Resolved once per
  /// invocation alongside [_gitSha]; false when not in a git checkout, true
  /// when `git status` cannot be determined (an unknown tree state must never
  /// auto-group or claim clean provenance).
  bool? _isTreeDirty;

  /// The correlation key used to make patch creation idempotent across
  /// platforms and invocations. Resolution order:
  ///
  /// 1. An explicit `--patch-id` is used as-is.
  /// 2. The `HEAD` commit SHA, when it identifies the code being shipped:
  ///    always on CI (tree dirt there is build-generated — lockfiles,
  ///    pod installs — not authored edits, and separate platform bots at the
  ///    same commit must converge on one patch number), and on a clean tree
  ///    locally. A dirty *local* tree means authored edits the SHA does not
  ///    capture; grouping on it could collide two different builds, so it is
  ///    skipped.
  /// 3. A fresh UUID on multi-platform invocations, so the platforms in this
  ///    single command still share one patch number.
  /// 4. Null otherwise — legacy behavior, the server allocates a fresh patch
  ///    number per call.
  ///
  /// Resolved on first read and cached for the rest of the command so every
  /// platform's `createPatch` sees the same value. Requires `argResults`,
  /// [_gitSha], and [_isTreeDirty] to be wired before first access — every
  /// code path through `run()` (and every test going through
  /// `runWithOverrides`) satisfies that.
  late final String? clientPatchId = _resolveClientPatchId();

  String? _resolveClientPatchId() {
    // `run()` already rejects an empty `--patch-id`, so non-null here implies
    // non-empty. Empty-to-null coalescence lives at the client boundary
    // (`CodePushClient.createPatch`) and stays the single normalizer.
    final explicit = results['patch-id'] as String?;
    if (explicit != null) return explicit;
    // Default the correlation key to the commit SHA so separate invocations
    // built from the same commit — e.g. an iOS bot and an Android bot cutting
    // the same merge commit — converge on one patch number with no flags.
    // Only when the SHA is honest about the code being shipped: on CI, or on
    // a clean local tree (see the doc comment on [clientPatchId]).
    if (_gitSha != null &&
        (shorebirdEnv.isRunningOnCI || !(_isTreeDirty ?? false))) {
      return _gitSha;
    }
    // No usable SHA: a multi-platform invocation still needs the platforms
    // in *this* command to share a number, so mint one key for the invocation.
    if (results.releaseTypes.length > 1) return const Uuid().v4();
    return null;
  }

  /// The commit SHA recorded on created patches for provenance and display,
  /// independent of the correlation key. Suffixed with `-dirty` when the
  /// working tree has uncommitted changes so the recorded provenance never
  /// claims a commit that doesn't match the shipped code. Null outside a git
  /// checkout.
  @visibleForTesting
  String? get gitShaForProvenance {
    final sha = _gitSha;
    if (sha == null) return null;
    return (_isTreeDirty ?? false) ? '$sha-dirty' : sha;
  }

  /// Resolves the `HEAD` commit SHA for the current project, or null when the
  /// patch is not being cut inside a git checkout (or git is unavailable).
  Future<String?> _resolveGitSha() async {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot();
    if (projectRoot == null) return null;
    try {
      return await git.revParse(revision: 'HEAD', directory: projectRoot.path);
    } on Exception {
      return null;
    }
  }

  /// Resolves whether the working tree has uncommitted changes. Returns false
  /// when not in a git checkout (dirtiness is meaningless there — [_gitSha]
  /// is null, so nothing groups and no provenance is recorded).
  Future<bool> _resolveTreeDirty() async {
    if (_gitSha == null) return false; // not a git checkout
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot();
    if (projectRoot == null) return false;
    try {
      final porcelain = await git.status(
        directory: projectRoot.path,
        args: ['--porcelain'],
      );
      return porcelain.isNotEmpty;
    } on Exception {
      // Fail toward dirty: with the tree state unknown, treating it as clean
      // could group a dirty local build under the commit's patch number and
      // record provenance claiming code that wasn't shipped. Dirty only
      // costs auto-grouping (and adds `-dirty` to the recorded SHA), which
      // is the safe direction.
      return true;
    }
  }

  /// Patches collected from each platform's [createPatch] run, used to emit
  /// a single aggregated success message after the fan-out completes.
  @visibleForTesting
  final platformPatches = <ReleasePlatform, CreatePatchResponse>{};

  /// Narrates the correlation decision so grouping never happens invisibly.
  ///
  /// - Explicit `--patch-id` equal to a dirty `HEAD` gets a warning: the user
  ///   asserted a SHA that does not match the working tree.
  /// - A defaulted SHA key gets an info line saying grouping is happening —
  ///   with an extra note on CI when the tree is dirty (build-generated dirt
  ///   is expected there; grouping proceeds).
  /// - A dirty local tree gets an info line saying grouping is NOT happening
  ///   and how to opt in.
  ///
  /// `run()` resolves [_gitSha] and [_isTreeDirty] before calling this;
  /// resolve on demand too so the method is self-contained when invoked
  /// directly (e.g. in isolation by a test).
  @visibleForTesting
  Future<void> logCorrelationDecision() async {
    final sha = _gitSha ??= await _resolveGitSha();
    final dirty = _isTreeDirty ??= await _resolveTreeDirty();
    final explicit = results['patch-id'] as String?;

    if (explicit != null) {
      if (explicit == sha && dirty) {
        logger.warn(
          '--patch-id is set to HEAD ($sha), but the working tree has '
          'uncommitted changes — this SHA does not identify the code being '
          'shipped.',
        );
      }
      return;
    }

    if (sha != null && clientPatchId == sha) {
      if (dirty) {
        // Only reachable on CI: a dirty local tree never defaults to the SHA.
        logger.info(
          'Working tree has uncommitted changes (common in CI builds); '
          'grouping this patch by HEAD ($sha) anyway. Pass --patch-id to set '
          'a different correlation key.',
        );
      } else {
        logger.info(
          'Grouping this patch by commit $sha — patches of this release '
          'built from the same commit will share one patch number.',
        );
      }
      return;
    }

    if (sha != null && dirty) {
      logger.info(
        'Working tree has uncommitted changes, so this patch will not '
        'auto-group with patches from other invocations. Commit your changes '
        'or pass --patch-id to group explicitly.',
      );
    }
  }

  /// Logs how to resume a partially-published multi-platform patch when the
  /// correlation key was minted for this invocation (a UUID that a plain
  /// re-run cannot reproduce). Without this, a retry would mint a *new* key
  /// and the remaining platforms would land under a different patch number —
  /// exactly the split numbering unified patches exist to prevent.
  @visibleForTesting
  void maybeLogResumeHint() {
    final explicit = results['patch-id'] as String?;
    if (explicit != null) return; // key is user-supplied and reproducible
    final key = clientPatchId;
    if (key == null || key == _gitSha) return; // no key, or reproducible SHA
    if (platformPatches.isEmpty) return; // nothing published yet

    final published = platformPatches.keys.map((p) => p.displayName).toList()
      ..sort();
    final number = platformPatches.values.first.number;
    logger.info(
      '\nPatch $number was already published for ${published.join(', ')} '
      'before this failure. To add the remaining platform(s) to patch '
      '$number, re-run patch for them with '
      '${lightCyan.wrap('--patch-id=$key')}.',
    );
  }

  @override
  Future<int> run() async {
    if (results.releaseTypes.isEmpty) {
      logger.err(
        '''No platforms were provided. Use the --platforms argument to provide one or more platforms''',
      );
      return ExitCode.usage.code;
    }

    if (results.wasParsed('staging')) {
      logger.err(
        '''The --staging flag is deprecated and will be removed in a future release. Use --track=staging instead.''',
      );
      return ExitCode.usage.code;
    }

    // Reject `--patch-id=` (present but empty) outright. The typical cause is
    // an unexpanded CI template variable; silently treating it as omitted
    // would mean a multi-platform invocation generates a fresh UUID per bot,
    // so iOS and Android never converge on the same patch number.
    final patchIdRaw = results['patch-id'] as String?;
    if (patchIdRaw != null && patchIdRaw.isEmpty) {
      logger.err(
        r'''--patch-id was provided but is empty. This usually means an unexpanded template variable in your CI config (e.g. --patch-id=${{ env.PATCH_SHA }} where PATCH_SHA is not set). Pass a non-empty value or omit the flag.''',
      );
      return ExitCode.usage.code;
    }

    // Resolve the HEAD SHA and tree dirtiness once, before the per-platform
    // fan-out. Together they determine the default correlation key (so
    // separate-invocation platforms group) and the provenance SHA recorded on
    // every patch. Must precede any `clientPatchId` access, which reads both.
    _gitSha = await _resolveGitSha();
    _isTreeDirty = await _resolveTreeDirty();
    await logCorrelationDecision();

    final patcherFutures = results.releaseTypes
        .map(_resolvePatcher)
        .map(createPatch);

    try {
      for (final patcherFuture in patcherFutures) {
        await patcherFuture;
      }
    } catch (_) {
      // A minted (UUID) correlation key is not reproducible by a plain
      // re-run; tell the user how to resume before surfacing the failure.
      maybeLogResumeHint();
      rethrow;
    }

    logUnifiedSuccess();

    return ExitCode.success.code;
  }

  /// Emits one aggregated success line per patch number that ended up with
  /// at least one published platform — replaces the old per-platform log
  /// that used to live inside the wrapper's `publishPatch`.
  @visibleForTesting
  void logUnifiedSuccess() {
    if (platformPatches.isEmpty) return;

    // Group platforms by the patch number they ended up under. Under unified
    // numbering this is almost always a single group, but pinning by number
    // keeps the message correct in degenerate cases (different releases per
    // platform, the user explicitly skipping --patch-id on a multi-platform
    // call against a server that hasn't been updated, etc.).
    final byPatchNumber = <int, List<ReleasePlatform>>{};
    for (final entry in platformPatches.entries) {
      byPatchNumber.putIfAbsent(entry.value.number, () => []).add(entry.key);
    }

    for (final number in byPatchNumber.keys.toList()..sort()) {
      final platforms =
          byPatchNumber[number]!.map((p) => p.displayName).toList()..sort();
      logger.success(
        '\n✅ Published Patch $number (${platforms.join(', ')})!',
      );
    }
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
  @visibleForTesting
  Future<void> createPatch(Patcher patcher) async {
    // Ensure the HEAD SHA and tree dirtiness are resolved before
    // `clientPatchId` (the default correlation key) or `gitShaForProvenance`
    // are read. `run()` resolves them up front; resolve on demand here too so
    // the method is self-contained (e.g. when invoked directly by a test) and
    // every platform in the fan-out shares the same cached values.
    _gitSha ??= await _resolveGitSha();
    _isTreeDirty ??= await _resolveTreeDirty();

    await patcher.assertPreconditions();
    await patcher.assertArgsAreValid();
    results.assertAbsentOrValidKeyPairOrCommands();

    try {
      await shorebirdValidator.validateFlavors(
        flavorArg: flavor,
        releasePlatform: patcher.releaseType.releasePlatform,
      );
    } on ValidationFailedException {
      throw ProcessExit(ExitCode.config.code);
    }

    await cache.updateAll();

    final app = await codePushClientWrapper.getApp(appId: appId);

    var inferredReleaseVersion = false;
    File? patchArtifactFile;
    final Release release;
    final releasePlatform = patcher.releaseType.releasePlatform;
    if (useLatestRelease) {
      final releases = await codePushClientWrapper.getReleases(appId: appId);
      releases
        ..removeWhere(
          (release) => !release.platformStatuses.keys.contains(releasePlatform),
        )
        ..sortByUpdatedAt();
      if (releases.isEmpty) {
        logger.warn(
          '''No ${releasePlatform.displayName} releases found for app $appId. You must first create a release before you can create a patch.''',
        );
        throw ProcessExit(ExitCode.usage.code);
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
      release = await promptForRelease(releasePlatform);
    } else {
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

    assertReleaseContainsPlatform(release: release, patcher: patcher);
    assertReleaseIsActive(release: release, patcher: patcher);

    try {
      await shorebirdFlutter.installRevision(revision: release.flutterRevision);
    } on Exception {
      throw ProcessExit(ExitCode.software.code);
    }

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

    // If the user explicitly passed --obfuscate but the release has no
    // obfuscation map, the patch would be obfuscated against a non-obfuscated
    // release, producing a broken patch.
    final userPassedObfuscate = results.flagPresent('obfuscate');
    if (userPassedObfuscate && obfuscationMapFile == null) {
      logger.err(
        '--obfuscate was passed, but the release was not built with '
        'obfuscation. A patch cannot change the obfuscation mode of a '
        'release.',
      );
      throw ProcessExit(ExitCode.software.code);
    }
    if (userPassedObfuscate && obfuscationMapFile != null) {
      logger.info(
        '--obfuscate is not needed for patching. Obfuscation is applied '
        'automatically when the release was built with --obfuscate.',
      );
    }

    patcher.obfuscationMapPath = obfuscationMapFile?.path;

    // Build extra args to inject into the Flutter build command. These use
    // --extra-gen-snapshot-options= because they're passed through Flutter's
    // build system, which forwards them to gen_snapshot. This is distinct from
    // patcher.obfuscationGenSnapshotArgs, which produces bare gen_snapshot
    // flags (e.g. --load-obfuscation-map=...) for direct gen_snapshot/linker
    // calls made by Apple patchers outside the Flutter build.
    final extraBuildArgs = <String>[];
    if (obfuscationMapFile != null) {
      extraBuildArgs.addAll([
        '--obfuscate',
        '--extra-gen-snapshot-options='
            '--load-obfuscation-map=${obfuscationMapFile.path}',
      ]);

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
    // Flutter requires --split-debug-info with --obfuscate. Auto-add it
    // if --obfuscate will be in the build args (from the user or from
    // the obfuscation map injection above) but --split-debug-info is not.
    final hasObfuscate =
        results.flagPresent('obfuscate') ||
        extraBuildArgs.contains('--obfuscate');
    final hasSplitDebugInfo = results.optionPresent('split-debug-info');
    if (hasObfuscate && !hasSplitDebugInfo) {
      extraBuildArgs.add(
        '--split-debug-info=${p.join('build', 'shorebird', 'symbols')}',
      );
    }
    patcher.extraBuildArgs = extraBuildArgs;

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: release.flutterRevision,
    );

    return await runScoped(
      () async {
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

        final dryRun = results['dry-run'] == true;
        if (dryRun) {
          logger
            ..info('No issues detected.')
            ..info('The server may enforce additional checks.');
          throw ProcessExit(ExitCode.success.code);
        }

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
            usesShorebirdCodePushPackage:
                shorebirdEnv.usesShorebirdCodePushPackage,
          ),
          // Attach the build-trace summary if the build produced one.
          // Null for older Flutter pins without the --shorebird-trace
          // flag or when trace parsing failed; uploader sends
          // null-as-omitted.
          buildTraceSummary: buildTraceSession.summary?.toJson(),
        );
        final updateMetadata = await patcher.updatedCreatePatchMetadata(
          baseMetadata,
        );

        final publishedPatch = await patcher.uploadPatchArtifacts(
          appId: appId,
          releaseId: release.id,
          metadata: updateMetadata.toJson(),
          track: track,
          artifacts: patchArtifactBundles,
          clientPatchId: clientPatchId,
          gitSha: gitShaForProvenance,
        );
        platformPatches[patcher.releaseType.releasePlatform] = publishedPatch;
      },
      values: {shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv)},
    );
  }

  /// Prompts the user for the specific release to patch.
  Future<Release> promptForRelease(ReleasePlatform platform) async {
    final releases = await codePushClientWrapper.getReleases(appId: appId);

    final releasesForPlatform = releases.where(
      (release) => release.platformStatuses.keys.contains(platform),
    );

    if (releasesForPlatform.isEmpty) {
      logger.warn(
        '''No ${platform.displayName} releases found for app $appId. You must first create a release before you can create a patch.''',
      );
      throw ProcessExit(ExitCode.usage.code);
    }

    return chooseRelease(
      releases: releasesForPlatform,
      action: 'patch',
    );
  }

  /// Asserts that the release contains a platform for the given [patcher].
  void assertReleaseContainsPlatform({
    required Release release,
    required Patcher patcher,
  }) {
    final releasePlatform = patcher.releaseType.releasePlatform;
    final contains = release.platformStatuses.containsKey(releasePlatform);
    if (!contains) {
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
    final releaseStatus =
        release.platformStatuses[patcher.releaseType.releasePlatform];
    if (releaseStatus != ReleaseStatus.active) {
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
      return patcher.assertUnpatchableDiffs(
        releaseArtifact: releaseArtifact,
        releaseArchive: releaseArchive,
        patchArchive: patchArchive,
      );
    } on UserCancelledException {
      throw ProcessExit(ExitCode.success.code);
    } on UnpatchableChangeException {
      logger.info('Exiting.');
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
      logger.err(
        '--min-link-percentage must be an integer between '
        '${CommonArguments.minLinkPercentageMin} and '
        '${CommonArguments.minLinkPercentageMax} '
        '(got $minLinkPercentageRaw).',
      );
      throw ProcessExit(ExitCode.usage.code);
    }
    if (linkPercentage != null && linkPercentage < minLinkPercentage) {
      logger.err(
        '''The link percentage of this patch ($linkPercentage%) is below the minimum threshold ($minLinkPercentage%). Exiting.''',
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

    if (confirm && shorebirdEnv.canAcceptUserInput) {
      if (!logger.confirm('Would you like to continue?', defaultValue: true)) {
        logger.info('Aborting.');
        throw ProcessExit(ExitCode.success.code);
      }
    }
  }

  /// Downloads the given [releaseArtifact].
  Future<File> downloadReleaseArtifact({
    required ReleaseArtifact releaseArtifact,
  }) async {
    final File artifactFile;
    try {
      artifactFile = await artifactManager.downloadWithProgressUpdates(
        Uri.parse(releaseArtifact.url),
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
