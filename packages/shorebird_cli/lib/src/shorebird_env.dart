import 'dart:io' hide Platform;

import 'package:checked_yaml/checked_yaml.dart';
import 'package:cli_util/cli_util.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/ci_provider.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Exception thrown when the Shorebird cache appears to be corrupted.
class CacheCorruptedException implements Exception {
  /// Creates a [CacheCorruptedException] explaining why the cache is
  /// considered corrupted via [reason] (a complete sentence).
  ///
  /// [remedy] is the advice shown after [reason]. It defaults to wiping the
  /// whole cache, which is the right answer only when nothing narrower is
  /// known: that wipe takes every installed Flutter revision with it, so a
  /// caller that can name a smaller repair should pass it.
  const CacheCorruptedException(
    this.reason, {
    this.remedy =
        'Your Shorebird installation may be corrupted. '
        "Try running 'shorebird cache clean' and retrying.",
  });

  /// Human-readable explanation of why the cache is considered corrupted.
  final String reason;

  /// Human-readable advice on how to recover.
  final String remedy;

  @override
  String toString() => '$reason $remedy';
}

/// The Shorebird auth service the CLI uses unless `AUTH_SERVICE_URL` names
/// another.
const defaultAuthServiceUrl = 'https://auth.shorebird.dev';

/// Where Flutter downloads its engine and SDK artifacts from unless
/// `SHOREBIRD_DOWNLOAD_URL` names another, such as a mirror.
const defaultDownloadUrl = 'https://download.shorebird.dev';

/// The Shorebird Flutter fork the CLI clones unless
/// `SHOREBIRD_FLUTTER_GIT_URL` names another, such as a mirror.
const defaultFlutterGitUrl = 'https://github.com/shorebirdtech/flutter.git';

/// The bundletool jar the CLI downloads unless `SHOREBIRD_BUNDLETOOL_URL`
/// names another, such as a mirror. Whichever URL serves it, the jar must
/// match the checksum the CLI expects.
const defaultBundletoolUrl =
    'https://github.com/google/bundletool/releases/download/${BundleToolArtifact.version}/bundletool-all-${BundleToolArtifact.version}.jar';

/// The code push server the hidden `--dev` flag selects.
const devHostedUrl = 'https://api-dev.shorebird.dev';

/// The auth service the hidden `--dev` flag selects.
const devAuthServiceUrl = 'https://auth-dev.shorebird.dev';

/// The Shorebird web console for the production code push server.
const defaultConsoleUrl = 'https://console.shorebird.dev';

/// The Shorebird web console the hidden `--dev` flag selects.
const devConsoleUrl = 'https://console-dev.shorebird.dev';

/// A Shorebird-hosted environment: a code push server, the auth service whose
/// tokens it accepts, and the web console that manages it.
///
/// The one place these are paired, so that whichever way the CLI is pointed
/// at a server (`--dev`, `SHOREBIRD_HOSTED_URL`, or `base_url` in
/// shorebird.yaml) its auth service and console follow from it, and cannot
/// drift from it.
typedef ShorebirdEnvironment = ({
  String hostedUrl,
  String authServiceUrl,
  String consoleUrl,
});

/// The production environment, which the CLI uses by default.
const productionEnvironment = (
  hostedUrl: 'https://api.shorebird.dev',
  authServiceUrl: defaultAuthServiceUrl,
  consoleUrl: defaultConsoleUrl,
);

/// The dev environment, which the hidden `--dev` flag selects.
const devEnvironment = (
  hostedUrl: devHostedUrl,
  authServiceUrl: devAuthServiceUrl,
  consoleUrl: devConsoleUrl,
);

/// The Shorebird-hosted environments, matched by the host of their code push
/// server (see [ShorebirdEnv.hostedEnvironment]).
const shorebirdEnvironments = [productionEnvironment, devEnvironment];

/// A reference to whether the hidden `--dev` global flag was passed.
final isDevModeRef = create(() => false);

/// Whether the hidden `--dev` global flag was passed: the CLI talks to
/// [devEnvironment] unless `SHOREBIRD_HOSTED_URL` or `AUTH_SERVICE_URL`
/// name another server.
bool get isDevMode => read(isDevModeRef, orElse: () => false);

/// A reference to a [ShorebirdEnv] instance.
final shorebirdEnvRef = create(ShorebirdEnv.new);

/// The [ShorebirdEnv] instance available in the current zone.
ShorebirdEnv get shorebirdEnv => read(shorebirdEnvRef);

/// {@template shorebird_env}
/// A class that provides access to shorebird environment metadata.
/// {@endtemplate}
class ShorebirdEnv {
  /// {@macro shorebird_env}
  const ShorebirdEnv({
    String? flutterRevisionOverride,
    String? flutterProjectRootOverride,
  }) : _flutterRevisionOverride = flutterRevisionOverride,
       _flutterProjectRootOverride = flutterProjectRootOverride;

  /// Copy the [ShorebirdEnv] and optionally override the flutter revision.
  ShorebirdEnv copyWith({String? flutterRevisionOverride}) => ShorebirdEnv(
    flutterRevisionOverride:
        flutterRevisionOverride ?? _flutterRevisionOverride,
  );

  final String? _flutterRevisionOverride;
  final String? _flutterProjectRootOverride;

  /// The application config directory for the Shorebird CLI, found from the
  /// scoped [platform]'s environment (`HOME`, `XDG_CONFIG_HOME` or `APPDATA`)
  /// so that tests can point it at a temporary directory.
  Directory get configDirectory {
    return Directory(
      BaseDirectories(
        executableName,
        environment: platform.environment,
      ).configHome,
    );
  }

  /// The directory where shorebird logs are stored.
  Directory get logsDirectory {
    return Directory(p.join(configDirectory.path, 'logs'));
  }

  /// The root directory of the Shorebird install.
  ///
  /// Assumes we are running from $ROOT/bin/cache.
  Directory get shorebirdRoot {
    return File(platform.script.toFilePath()).parent.parent.parent;
  }

  /// The Shorebird engine revision.
  String get shorebirdEngineRevision {
    final file = File(
      p.join(flutterDirectory.path, 'bin', 'internal', 'engine.version'),
    );
    try {
      return file.readAsStringSync().trim();
    } on FileSystemException {
      throw CacheCorruptedException('Could not read ${file.path}.');
    }
  }

  /// Get the Shorebird Flutter revision.
  String get flutterRevision {
    if (_flutterRevisionOverride != null) return _flutterRevisionOverride;
    final file = File(
      p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'),
    );
    try {
      return file.readAsStringSync().trim();
    } on FileSystemException {
      throw CacheCorruptedException('Could not read ${file.path}.');
    }
  }

  /// Whether the project uses package:shorebird_code_push.
  bool get usesShorebirdCodePushPackage {
    final pubspec = getPubspecYaml();
    return pubspec?.dependencies.containsKey('shorebird_code_push') ?? false;
  }

  /// The root of the Shorebird-vended Flutter git checkout.
  Directory get flutterDirectory {
    return Directory(
      p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter', flutterRevision),
    );
  }

  /// The Shorebird-vended Flutter binary.
  File get flutterBinaryFile {
    final flutter = platform.isWindows ? 'flutter.bat' : 'flutter';
    return File(p.join(flutterDirectory.path, 'bin', flutter));
  }

  /// The Shorebird-vended Dart binary.
  File get dartBinaryFile {
    final dart = platform.isWindows ? 'dart.bat' : 'dart';
    return File(p.join(flutterDirectory.path, 'bin', dart));
  }

  /// The Cocoapods lockfile for this project's iOS app.
  File get iosPodfileLockFile {
    return File(p.join(getFlutterProjectRoot()!.path, 'ios', 'Podfile.lock'));
  }

  /// The hash of the Podfile.lock file for this project's iOS app. Will be null
  /// if the file does not exist.
  String? get iosPodfileLockHash {
    if (!iosPodfileLockFile.existsSync()) return null;
    return sha256.convert(iosPodfileLockFile.readAsBytesSync()).toString();
  }

  /// The Cocoapods lockfile for this project's macOS app.
  File get macosPodfileLockFile {
    return File(p.join(getFlutterProjectRoot()!.path, 'macos', 'Podfile.lock'));
  }

  /// The hash of the Podfile.lock file for this project's macOS app. Will be
  /// null if the file does not exist.
  String? get macosPodfileLockHash {
    if (!macosPodfileLockFile.existsSync()) return null;
    return sha256.convert(macosPodfileLockFile.readAsBytesSync()).toString();
  }

  /// The build directory of the current shorebird project.
  Directory get buildDirectory {
    return Directory(p.join(getFlutterProjectRoot()!.path, 'build'));
  }

  /// Where the link supplement files are stored.
  // TODO(eseidel): Make this not iOS specific.
  Directory get iosSupplementDirectory =>
      Directory(p.join(buildDirectory.path, 'ios', 'shorebird'));

  /// The `shorebird.yaml` file for this project.
  File getShorebirdYamlFile({required Directory cwd}) {
    return File(p.join(cwd.path, 'shorebird.yaml'));
  }

  /// The `pubspec.yaml` file for this project.
  File getPubspecYamlFile({required Directory cwd}) {
    return File(p.join(cwd.path, 'pubspec.yaml'));
  }

  /// Finds nearest ancestor file
  /// relative to the [cwd] that satisfies [where].
  File? findNearestAncestor({
    required File? Function(String path) where,
    Directory? cwd,
  }) {
    Directory? prev;
    var dir = cwd ?? Directory.current;
    while (prev?.path != dir.path) {
      final file = where(dir.path);
      if (file?.existsSync() ?? false) return file;
      prev = dir;
      dir = dir.parent;
    }
    return null;
  }

  /// Returns the root directory of the nearest Shorebird project.
  Directory? getShorebirdProjectRoot() {
    final file = findNearestAncestor(
      where: (path) => getShorebirdYamlFile(cwd: Directory(path)),
    );
    if (file == null || !file.existsSync()) return null;
    return Directory(p.dirname(file.path));
  }

  /// Returns the root directory of the nearest Flutter project.
  Directory? getFlutterProjectRoot() {
    if (_flutterProjectRootOverride != null) {
      return Directory(_flutterProjectRootOverride);
    }
    final file = findNearestAncestor(
      where: (path) => getPubspecYamlFile(cwd: Directory(path)),
    );
    if (file == null || !file.existsSync()) return null;
    return Directory(p.dirname(file.path));
  }

  /// The `shorebird.yaml` file for this project, parsed into a [ShorebirdYaml]
  /// object.
  ///
  /// Returns `null` if the file does not exist.
  /// Throws a [ParsedYamlException] if the file exists but is invalid.
  ShorebirdYaml? getShorebirdYaml() {
    final root = getShorebirdProjectRoot();
    if (root == null) return null;
    final yaml = getShorebirdYamlFile(cwd: root).readAsStringSync();
    return checkedYamlDecode(yaml, (m) => ShorebirdYaml.fromJson(m!));
  }

  /// The `pubspec.yaml` file for this project, parsed into a [Pubspec] object.
  ///
  /// Returns `null` if the file does not exist.
  /// Throws a [ParsedYamlException] if the file exists but is invalid.
  Pubspec? getPubspecYaml() {
    final root = getFlutterProjectRoot();
    if (root == null) return null;
    try {
      final yaml = getPubspecYamlFile(cwd: root).readAsStringSync();
      return Pubspec.parse(yaml, lenient: true);
    } on Exception {
      return null;
    }
  }

  /// Whether the current project has a `shorebird.yaml` file.
  bool get hasShorebirdYaml => getShorebirdYaml() != null;

  /// Whether the current project has a `pubspec.yaml` file.
  bool get hasPubspecYaml => getPubspecYaml() != null;

  /// Whether the current project's `pubspec.yaml` file contains a reference to
  /// `shorebird.yaml` in its `assets` section.
  bool get pubspecContainsShorebirdYaml {
    final pubspec = getPubspecYaml();
    if (pubspec == null) return false;
    if (pubspec.flutter == null) return false;
    if (pubspec.flutter!['assets'] == null) return false;
    final assets = pubspec.flutter!['assets'] as List;
    return assets.contains('shorebird.yaml');
  }

  /// Returns the Android package name from the pubspec.yaml file of a Flutter
  /// module.
  String? get androidPackageName {
    final pubspec = getPubspecYaml();
    final module = pubspec?.flutter?['module'] as Map?;
    return module?['androidPackage'] as String?;
  }

  /// The base URL for the Shorebird auth service: the
  /// `AUTH_SERVICE_URL` environment variable when it is set, otherwise the
  /// auth service of the [hostedEnvironment] the CLI talks to (so `--dev`,
  /// or `SHOREBIRD_HOSTED_URL` naming the dev server, selects
  /// [devAuthServiceUrl]), otherwise [defaultAuthServiceUrl].
  Uri get authServiceUri => Uri.parse(
    _environmentOverride('AUTH_SERVICE_URL') ??
        hostedEnvironment?.authServiceUrl ??
        defaultAuthServiceUrl,
  );

  /// The Shorebird-hosted environment whose code push server [hostedUri]
  /// names, matched by host: [productionEnvironment] when [hostedUri] is
  /// null, and null for a server Shorebird does not host, such as a local
  /// one.
  ShorebirdEnvironment? get hostedEnvironment {
    final hosted = hostedUri;
    if (hosted == null) return productionEnvironment;
    return shorebirdEnvironments
        .where((env) => Uri.parse(env.hostedUrl).host == hosted.host)
        .firstOrNull;
  }

  /// Why the code push server may refuse the auth service's tokens, with
  /// what to set, or null when the two belong together (or the CLI cannot
  /// tell): `AUTH_SERVICE_URL` names a different auth service from the one
  /// a Shorebird-hosted server accepts, or the server is not one Shorebird
  /// hosts and `AUTH_SERVICE_URL` is unset, so the CLI fell back to
  /// [defaultAuthServiceUrl].
  String? get authServiceMismatch {
    final authOverride = _environmentOverride('AUTH_SERVICE_URL');
    final environment = hostedEnvironment;
    final serverHost =
        hostedUri?.host ?? Uri.parse(productionEnvironment.hostedUrl).host;
    if (environment == null) {
      if (authOverride != null) return null;
      return '$serverHost is not a Shorebird-hosted server, so the CLI '
          'signed in with $defaultAuthServiceUrl. If $serverHost uses '
          'another auth service, set AUTH_SERVICE_URL to it, then run '
          'shorebird login.';
    }
    if (authOverride == null) return null;
    final expected = Uri.parse(environment.authServiceUrl);
    if (Uri.parse(authOverride).host == expected.host) return null;
    return '$serverHost accepts tokens from ${environment.authServiceUrl}, '
        'but AUTH_SERVICE_URL is $authOverride. Unset AUTH_SERVICE_URL (or '
        'set it to ${environment.authServiceUrl}), then run shorebird login.';
  }

  /// The base URL Flutter downloads its artifacts from, passed to Flutter as
  /// `FLUTTER_STORAGE_BASE_URL`: the `SHOREBIRD_DOWNLOAD_URL`
  /// environment variable when it is set, otherwise [defaultDownloadUrl].
  ///
  /// Point this at a mirror of [defaultDownloadUrl] (for example an
  /// Artifactory remote repository) or a local server. A user's own
  /// `FLUTTER_STORAGE_BASE_URL` is deliberately not used: it usually names a
  /// mirror of Google's Flutter artifacts, which lacks Shorebird's engine.
  ///
  /// The CLI's own per-engine tools come from here too, under
  /// `shorebird/<engine revision>/`, so a mirror of this one host covers
  /// every artifact the CLI downloads.
  String get downloadUrl {
    final override = _environmentOverride('SHOREBIRD_DOWNLOAD_URL');
    if (override == null) return defaultDownloadUrl;
    // Flutter appends paths that begin with '/'.
    return override.endsWith('/')
        ? override.substring(0, override.length - 1)
        : override;
  }

  /// The git URL of the Shorebird Flutter fork: the
  /// `SHOREBIRD_FLUTTER_GIT_URL` environment variable when it is set,
  /// otherwise [defaultFlutterGitUrl].
  String get flutterGitUrl =>
      _environmentOverride('SHOREBIRD_FLUTTER_GIT_URL') ?? defaultFlutterGitUrl;

  /// The URL of the bundletool jar: the `SHOREBIRD_BUNDLETOOL_URL`
  /// environment variable when it is set, otherwise [defaultBundletoolUrl].
  String get bundletoolUrl =>
      _environmentOverride('SHOREBIRD_BUNDLETOOL_URL') ?? defaultBundletoolUrl;

  /// The value of the environment variable [name], or null when it is unset
  /// or empty.
  String? _environmentOverride(String name) {
    final value = platform.environment[name];
    return value == null || value.isEmpty ? null : value;
  }

  /// The base URL for the Shorebird code push server that overrides the default
  /// used by [CodePushClient]: the `SHOREBIRD_HOSTED_URL` environment
  /// variable when it is set, otherwise [devHostedUrl] with `--dev` (see
  /// [isDevMode]), otherwise the `base_url` in shorebird.yaml. If none is
  /// provided, [CodePushClient] will use its default.
  Uri? get hostedUri {
    try {
      final baseUrl =
          _environmentOverride('SHOREBIRD_HOSTED_URL') ??
          (isDevMode ? devHostedUrl : getShorebirdYaml()?.baseUrl);
      return baseUrl == null ? null : Uri.tryParse(baseUrl);
    } on Exception {
      return null;
    }
  }

  /// Whether the CLI can prompt the user (`confirm`, `chooseOne`, `prompt`).
  ///
  /// Returns `false` when stdin is not a terminal, when stdout cannot render
  /// a prompt, when running on CI, or when the user has opted into
  /// non-interactive output via `--json`.
  ///
  /// Prompts need `stdout.hasTerminal` specifically: mason_logger's prompts
  /// throw `NoTerminalAttachedError` without it. That is stricter than
  /// `isInteractive`, which also accepts stdout redirected to `/dev/null` and
  /// PTYs with no window size, where spinners still work but prompts do not.
  bool get canAcceptUserInput =>
      stdin.hasTerminal && stdout.hasTerminal && !isRunningOnCI && !isJsonMode;

  /// Whether platform.environment indicates that we are running on a CI
  /// platform. See [ciProvider].
  bool get isRunningOnCI => ciProvider(platform.environment) != null;
}
