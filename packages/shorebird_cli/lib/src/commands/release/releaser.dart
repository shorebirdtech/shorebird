import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/build_flags.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/split_debug_info.dart';
import 'package:shorebird_cli/src/symbols/sbsymbols.dart';
import 'package:shorebird_cli/src/symbols/symbol_extractor.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:yaml/yaml.dart';

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
  Version get minimumFlutterVersion =>
      minimumReleaseFlutterVersion(releaseType);

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// Whether this run may add its artifacts to [release], which is already
  /// active on this platform. Most platforms build every architecture in one
  /// run, so a second release of the same version is refused; Windows builds
  /// one architecture per machine and adds the other to the same release.
  Future<bool> addsToActiveRelease(Release release) async => false;

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// The human-readable description of the release artifact being built (e.g.,
  /// "Android app", "iOS app").
  String get artifactDisplayName;

  /// Asserts that the command can be run.
  Future<void> assertPreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> assertArgsAreValid();

  /// Requires `--release-version` with a concrete version, for add-to-app
  /// releases (aar, ios-framework), whose version cannot be read from the
  /// built module: the developer names each module build.
  /// Rejects a missing, blank or `latest` value.
  void assertReleaseVersionProvided() {
    final value = (argResults['release-version'] as String?)?.trim();
    if (value == null || value.isEmpty || value == 'latest') {
      throw CommandError(
        message:
            'An ${releaseType.cliName} release needs --release-version: the '
            'version of this module build, a new one for each build you '
            'release.',
        hint: 'Run: ${releaseType.releaseCommand()}',
      );
    }
  }

  /// Rejects a `--release-version` the updater won't accept once it is built
  /// into the module, which Flutter
  /// [minimumModuleReleaseVersionFlutterVersion] and later do. Call before the
  /// build, with the release's Flutter installed. With an earlier Flutter the
  /// value is still the host app's version, which can be free text (Android's
  /// `versionName`), so it isn't checked.
  Future<void> assertReleaseVersionCanBeBuiltIn() async {
    final flutterVersion = await shorebirdFlutter.getVersion();
    if (flutterVersion == null ||
        flutterVersion < minimumModuleReleaseVersionFlutterVersion) {
      return;
    }
    final value = (argResults['release-version'] as String).trim();
    if (!_moduleReleaseVersionPattern.hasMatch(value)) {
      throw CommandError(
        message:
            '--release-version "$value" can only use letters, digits, '
            '".", "_", "+" and "-", up to 128 characters.',
        hint: 'Run: ${releaseType.releaseCommand()}',
      );
    }
  }

  static final _moduleReleaseVersionPattern = RegExp(
    r'^[A-Za-z0-9._+-]{1,128}$',
  );

  /// The app ID an add-to-app module (aar, ios-framework) released with
  /// `--flavor` is built with: the flavor's, in place of the checked-in
  /// shorebird.yaml's top-level `app_id` Flutter would build in. Null without
  /// `--flavor`.
  String? get moduleAppId => flavor == null
      ? null
      : shorebirdEnv.getShorebirdYaml()!.getAppId(
          flavor: flavor,
        );

  /// With `--flavor`, rejects a module build whose generated (bundled)
  /// shorebird.yaml, as [readBundledShorebirdYaml] returns it (null if the
  /// build has none), doesn't carry [moduleAppId]. The apps that embed it
  /// would check for patches under that other app ID and never get this
  /// release's. Flutter before 3.50.0 (shorebirdtech/flutter#358) ignores the
  /// app ID the CLI hands it and builds every module with the top-level
  /// `app_id` (shorebird#3746). Does nothing without `--flavor`.
  Future<void> assertModuleCarriesAppId(
    Future<String?> Function() readBundledShorebirdYaml,
  ) async {
    final expected = moduleAppId;
    if (expected == null) return;
    final actual = _appIdIn(await readBundledShorebirdYaml());
    if (actual == expected) return;
    if (actual == null) {
      throw CommandError(
        message:
            "Couldn't read the app ID from this module's generated "
            'shorebird.yaml, so the CLI cannot check that it carries '
            '$expected, the app ID of flavor "$flavor".',
        hint:
            'Please file an issue: '
            'https://github.com/shorebirdtech/shorebird/issues/new',
        exitCode: ExitCode.software,
      );
    }
    throw CommandError(
      message:
          'This module was built with app ID $actual, not $expected, the app '
          'ID of flavor "$flavor" in shorebird.yaml, so the apps that embed '
          'it would never get its patches. This Flutter version builds a '
          'module with the top-level app_id only.',
      hint:
          'Release with Flutter 3.50.0 or newer '
          '(--flutter-version=3.50.0), or with the '
          "flavor's app ID as the top-level app_id and no --flavor.",
      exitCode: ExitCode.config,
    );
  }

  static String? _appIdIn(String? shorebirdYaml) {
    if (shorebirdYaml == null) return null;
    try {
      final yaml = loadYaml(shorebirdYaml);
      return yaml is Map ? yaml['app_id']?.toString() : null;
    } on YamlException {
      return null;
    }
  }

  /// Rejects `--release-version`, which is only valid for releases whose
  /// version cannot be inferred from the built artifact (aar, ios-framework).
  /// Call from [assertArgsAreValid] in releasers that read the version from
  /// the built app.
  void assertReleaseVersionFlagNotProvided() {
    if (argResults.wasParsed('release-version')) {
      throw CommandError(
        message:
            '--release-version is only supported for aar and ios-framework '
            'releases.',
        hint:
            'Remove --release-version. This release takes its version from '
            'your pubspec.yaml.',
      );
    }
  }

  /// Builds the release artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  ///
  /// Implementations run their Flutter build through [runReleaseBuild].
  Future<FileSystemEntity> buildReleaseArtifacts();

  /// Runs a release's Flutter [build] with the arguments every release build
  /// shares, then checks the build produced what those arguments promised.
  ///
  /// Before building, [clearSupplementDirectory] removes the previous build's
  /// supplement output. [build] receives the user's forwarded arguments plus
  /// the `--split-debug-info` default and obfuscation map options (see
  /// [addSplitDebugInfoDefault] and [addObfuscationMapArgs]), and the encoded
  /// public key (see [resolvePatchSigningKey]). Once it returns,
  /// [verifyObfuscationMap] checks that an obfuscated build saved its
  /// obfuscation map.
  Future<T> runReleaseBuild<T>(
    Future<T> Function(List<String> buildArgs, String? base64PublicKey) build,
  ) async {
    clearSupplementDirectory();
    final base64PublicKey = await resolvePatchSigningKey();
    final buildArgs = [...argResults.forwardedArgs];
    addSplitDebugInfoDefault(buildArgs);
    await addObfuscationMapArgs(buildArgs);
    final result = await build(buildArgs, base64PublicKey);
    verifyObfuscationMap();
    return result;
  }

  /// Uploads the release artifacts to the CodePush server.
  ///
  /// The supplement artifact is uploaded separately, by
  /// [uploadSupplementArtifact].
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

  /// How this platform's build is signed for patch signing. Set by
  /// [resolvePatchSigningKey]; null until the build runs.
  ArtifactSigningRequest? signing;

  /// Decides which public key this platform's build embeds, sets [signing]
  /// to match, and returns the key base64-encoded, or null if the build
  /// embeds none.
  ///
  /// A key passed with --public-key-path or --public-key-cmd is the
  /// customer's, who signs every patch. Otherwise the build embeds the
  /// managed key the server returns for the app, and Shorebird signs every
  /// patch; a failed fetch fails the release, so it never silently goes
  /// unsigned. With --no-patch-signing the build embeds no key.
  Future<String?> resolvePatchSigningKey() async {
    final customerKey = await getEncodedPublicKey();
    if (customerKey != null) {
      signing = const ArtifactSigningRequest(
        mode: ReleaseSigningMode.customer,
      );
      return customerKey;
    }
    if (!argResults.patchSigningEnabled) {
      signing = const ArtifactSigningRequest(
        mode: ReleaseSigningMode.unsigned,
      );
      return null;
    }
    final SigningKey signingKey;
    try {
      signingKey = await codePushClientWrapper.getSigningKey(
        appId: shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor),
      );
    } on ProcessExit {
      // The fetch already said why it failed; say what the user can do.
      logger.info(
        'Releases embed a Shorebird-managed patch signing key by default. '
        'To release without one (patches will be unsigned), pass '
        '--no-${CommonArguments.patchSigningArg.name}.',
      );
      rethrow;
    }
    signing = ArtifactSigningRequest(
      mode: ReleaseSigningMode.managed,
      keyId: signingKey.id,
    );
    return codeSigner.base64PublicKeyFromPem(signingKey.publicKeyPem);
  }

  /// Whether the user is building with obfuscation. Checks for `--obfuscate`
  /// both as a parsed flag and after the `--` separator, since it can be
  /// passed either to Shorebird directly or forwarded to Flutter.
  bool get useObfuscation => argResults.flagPresent('obfuscate');

  /// The Dynamic Dispatch (DD) table cascade byte threshold the user set
  /// with `--dd-max-bytes`, or null when they set none (or a malformed or
  /// negative value). `0` turns DD off.
  ///
  /// A debugging option; unset, the build's own default applies. How it
  /// reaches the build depends on the Flutter version; see
  /// `ArtifactBuilder._iosDdSettings`.
  int? get ddMaxBytes {
    final value = argResults[CommonArguments.ddMaxBytesArg.name] as String?;
    if (value == null) return null;
    final parsed = int.tryParse(value);
    return (parsed != null && parsed >= 0) ? parsed : null;
  }

  /// Path where the obfuscation map is saved during obfuscated builds: the
  /// user's own `--save-obfuscation-map` path if they passed one (relative
  /// paths are resolved against the project root, where Flutter builds), or
  /// `build/shorebird/obfuscation_map.json` otherwise.
  String get obfuscationMapPath {
    final userPath = userObfuscationMapPath;
    if (userPath != null) {
      return p.normalize(p.join(projectRoot.path, userPath));
    }
    return p.join(
      projectRoot.path,
      'build',
      'shorebird',
      'obfuscation_map.json',
    );
  }

  /// The path the user passed to gen_snapshot's `--save-obfuscation-map`
  /// through `--extra-gen-snapshot-options`, or null if they didn't.
  ///
  /// Flutter splits `--extra-gen-snapshot-options` values on commas, and
  /// gen_snapshot honors the last `--save-obfuscation-map`, so this returns
  /// the last one.
  String? get userObfuscationMapPath {
    const extraOptionsPrefix = '--extra-gen-snapshot-options=';
    const saveMapPrefix = '--save-obfuscation-map=';
    String? path;
    for (final arg in argResults.forwardedArgs) {
      final value = arg.startsWith(extraOptionsPrefix)
          ? arg.substring(extraOptionsPrefix.length)
          : arg;
      for (final option in value.split(',')) {
        if (option.startsWith(saveMapPrefix)) {
          path = option.substring(saveMapPrefix.length);
        }
      }
    }
    return path;
  }

  /// Auto-adds --split-debug-info when --obfuscate is used without it.
  void addSplitDebugInfoDefault(List<String> buildArgs) {
    final splitDebugInfo = splitDebugInfoDefault(
      obfuscate: useObfuscation,
      hasSplitDebugInfo: buildArgs.any(
        (a) => a.startsWith('--split-debug-info'),
      ),
    );
    if (splitDebugInfo != null) buildArgs.add(splitDebugInfo);
  }

  /// Adds obfuscation-related gen_snapshot options to [buildArgs].
  ///
  /// When obfuscation is enabled, passes --save-obfuscation-map to capture
  /// the mapping, unless the user passed their own (see
  /// [userObfuscationMapPath]), which is kept and read from instead, since
  /// gen_snapshot writes only one map. Conditionally passes --strip to
  /// remove unobfuscated DWARF debugging information from the compiled
  /// snapshot, since the DWARF sections would otherwise leak identifiers
  /// that obfuscation was meant to hide.
  ///
  /// On Android, --strip is only passed for Flutter versions older than
  /// 3.44. From 3.44 onward, upstream Flutter PR
  /// https://github.com/flutter/flutter/pull/181275 (merged 2026-01-26)
  /// made AGP responsible for stripping `libapp.so` and emitting the
  /// matching `.sym` companion into the AAB's BUNDLE-METADATA. Passing
  /// --strip to gen_snapshot on 3.44+ pre-strips the snapshot, leaving AGP
  /// with nothing to strip. flutter_tools then fails the build with
  /// "libapp.so.sym or libapp.so.dbg not present when checking final
  /// appbundle for debug symbols." Letting AGP do the stripping preserves
  /// the obfuscation protection in the user-shipped APK (AGP uses
  /// `llvm-strip --strip-unneeded`, which removes the same DWARF sections
  /// that gen_snapshot --strip would have), while restoring the `.sym`
  /// companion that 3.44 requires. The `.sym` file containing the
  /// pre-strip DWARF is only retained in BUNDLE-METADATA, which Play
  /// strips before delivery to end-user devices, so the only readers are
  /// the developer's own Play Console crash dashboard.
  ///
  /// On non-Android platforms (iOS, macOS, Linux, Windows, iOS framework,
  /// AAR), AGP is not in the pipeline, so --strip is always passed
  /// regardless of Flutter version.
  Future<void> addObfuscationMapArgs(List<String> buildArgs) async {
    if (!useObfuscation) return;
    final mapDir = Directory(p.dirname(obfuscationMapPath));
    if (!mapDir.existsSync()) mapDir.createSync(recursive: true);
    if (userObfuscationMapPath == null) {
      buildArgs.add(
        '--extra-gen-snapshot-options='
        '--save-obfuscation-map=$obfuscationMapPath',
      );
    }

    final shouldPreStripInGenSnapshot = await shorebirdFlutter
        .shouldPreStripLibappInGenSnapshot(
          platform: releaseType.releasePlatform,
          flutterRevision: shorebirdEnv.flutterRevision,
        );

    if (shouldPreStripInGenSnapshot) {
      buildArgs.add('--extra-gen-snapshot-options=--strip');
    }
  }

  /// Whether the app has opted in to Crash Reporting, set by `shorebird
  /// release` from `getApp` before building. Symbol index extraction and
  /// upload both sit behind this gate.
  bool crashReportingEnabled = false;

  /// Where this release's build writes its Dart symbols: the
  /// `--split-debug-info` directory the user passed, or the default
  /// Shorebird adds for an obfuscated release. Null when the build writes
  /// none.
  ///
  /// Read back off the arguments [runReleaseBuild] builds rather than from
  /// the user's argument alone, so it answers with the directory the build
  /// was actually given.
  String? get splitDebugInfoPath {
    final buildArgs = [...argResults.forwardedArgs];
    addSplitDebugInfoDefault(buildArgs);
    return splitDebugInfoDirectory(buildArgs);
  }

  /// The name the build gives each architecture's debug info in
  /// [splitDebugInfoPath]. Empty for a release type that does not upload
  /// symbol indexes.
  Map<Arch, String> get debugInfoFileNames => const {};

  /// The architectures this release's build produced, so [debugInfoFiles]
  /// ignores symbol files an earlier build left for architectures this build
  /// skipped.
  Set<Arch> get builtArchitectures => debugInfoFileNames.keys.toSet();

  /// The debug info this release's build left behind, by architecture.
  ///
  /// Only the architectures in [builtArchitectures] whose file exists: an
  /// architecture the build skipped, and a build that was given no
  /// `--split-debug-info`, leave nothing here.
  Map<Arch, File> get debugInfoFiles {
    final directory = splitDebugInfoPath;
    if (directory == null) return const {};
    final files = <Arch, File>{};
    for (final arch in builtArchitectures) {
      final name = debugInfoFileNames[arch];
      if (name == null) continue;
      final file = File(p.join(projectRoot.path, directory, name));
      if (file.existsSync()) files[arch] = file;
    }
    return files;
  }

  /// Where the SBSY v1 index extracted from [debugInfo] is written: beside
  /// it, under the same name.
  ///
  /// Outside the supplement directory on purpose. The supplement is zipped
  /// into a release artifact that every patch build of this release
  /// downloads, and a symbol index is read by crash symbolication alone.
  static File _symbolIndexFile(File debugInfo) =>
      File(p.setExtension(debugInfo.path, '.sbsymbols'));

  /// The indexes [extractSymbolIndexes] wrote, by architecture.
  ///
  /// Carried rather than read back off disk, because a release and the
  /// patches built against it share one `--split-debug-info` directory and
  /// so name their indexes the same file. A release that extracts none of its
  /// own would otherwise upload a patch's index as its own and name every
  /// frame after the patch's code.
  Map<Arch, File> _symbolIndexes = const {};

  /// Platform subdirectory for the supplement directory (e.g. 'android',
  /// 'ios'). Used to construct `build/<platformSubdir>/shorebird/`.
  String get supplementPlatformSubdir;

  /// Arch string for the supplement artifact on the server (e.g.
  /// 'android_supplement').
  String get supplementArtifactArch;

  /// Deletes `build/<supplementPlatformSubdir>/shorebird/` if it exists, so
  /// that files a previous build left there (e.g. link supplements written by
  /// an older Flutter that did not clear the directory itself) cannot be
  /// uploaded as part of this release.
  void clearSupplementDirectory() {
    final supplementDir = Directory(
      p.join(projectRoot.path, 'build', supplementPlatformSubdir, 'shorebird'),
    );
    if (!supplementDir.existsSync()) return;
    logger.detail('Deleting stale supplement directory ${supplementDir.path}');
    supplementDir.deleteSync(recursive: true);
  }

  /// Assembles the supplement directory: copies the obfuscation map (if
  /// present) into the platform supplement dir and writes the release's
  /// [BuildFlags]. Returns the directory, or null if there's no project.
  Directory? assembleSupplementDirectory() {
    final obfuscationMapFile = File(obfuscationMapPath);
    final hasObfuscationMap = useObfuscation && obfuscationMapFile.existsSync();
    final supplementDir = artifactManager.getReleaseSupplementDirectory(
      platformSubdir: supplementPlatformSubdir,
      create: true,
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

    // The build already read every --dart-define-from-file, so this reads
    // them again only to hash them.
    File(
      p.join(supplementDir.path, BuildFlags.fileName),
    ).writeAsStringSync(
      json.encode(BuildFlags.fromArgs(argResults, target: target).toJson()),
    );

    extractSymbolIndexes();

    return supplementDir;
  }

  /// Extracts a SBSY v1 index from each architecture's debug info when
  /// [crashReportingEnabled] is true, so a crash report's program counter
  /// offsets can be named without reading or uploading raw DWARF.
  @visibleForTesting
  void extractSymbolIndexes() {
    if (!crashReportingEnabled) {
      _symbolIndexes = const {};
      return;
    }
    final indexes = <Arch, File>{};
    for (final MapEntry(key: arch, value: debugInfo)
        in debugInfoFiles.entries) {
      final index = symbolExtractor.writeIndex(
        debugInfo: debugInfo,
        output: _symbolIndexFile(debugInfo),
        image: SymbolImage.release,
      );
      if (index == null) {
        logger.detail('No symbol index extracted from ${debugInfo.path}');
        continue;
      }
      indexes[arch] = index;
    }
    _symbolIndexes = indexes;
  }

  /// Uploads the supplement artifact (e.g. obfuscation map) if one was
  /// assembled. `shorebird release` calls this right after
  /// [uploadReleaseArtifacts].
  ///
  /// Both uploads run while the release is a draft on this platform, and
  /// `shorebird patch` refuses a release that is not active on its platform.
  /// A run stopped between them leaves a release nothing can patch until it
  /// is released again.
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
        signing: signing,
      );
    }
  }

  /// Uploads each architecture's SBSY v1 symbol index when
  /// [crashReportingEnabled] is true, which crash symbolication reads to name
  /// a crash report's frames.
  ///
  /// Only the indexes [extractSymbolIndexes] wrote go up, so this runs after
  /// [uploadSupplementArtifact], which is what assembles the supplement and
  /// extracts them.
  Future<void> uploadSymbolArtifacts({
    required String appId,
    required int releaseId,
  }) async {
    if (!crashReportingEnabled) return;
    for (final MapEntry(key: arch, value: index) in _symbolIndexes.entries) {
      await codePushClientWrapper.createReleaseSymbols(
        appId: appId,
        releaseId: releaseId,
        platform: releaseType.releasePlatform,
        arch: arch.arch,
        format: SymbolsFormat.sbsymbols,
        symbols: index,
      );
    }
  }

  /// Verifies the obfuscation map was generated after build.
  void verifyObfuscationMap() {
    if (!useObfuscation) return;
    final mapFile = File(obfuscationMapPath);
    if (!mapFile.existsSync()) {
      throw CommandError(
        message:
            'Obfuscation was enabled but the obfuscation map was not '
            'generated at $obfuscationMapPath.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }
    logger.detail('Obfuscation map saved to $obfuscationMapPath');
  }
}
