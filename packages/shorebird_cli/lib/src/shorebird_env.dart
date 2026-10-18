import 'dart:convert';
import 'dart:io' hide Platform;

import 'package:checked_yaml/checked_yaml.dart';
import 'package:cli_util/cli_util.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped_deps/scoped_deps.dart';
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

/// The code push server the hidden `--dev` flag selects.
const devHostedUrl = 'https://api-dev.shorebird.dev';

/// The auth service the hidden `--dev` flag selects.
const devAuthServiceUrl = 'https://auth-dev.shorebird.dev';

/// A reference to whether the hidden `--dev` global flag was passed.
final isDevModeRef = create(() => false);

/// Whether the hidden `--dev` global flag was passed: the CLI talks to the
/// dev environment ([devHostedUrl] and [devAuthServiceUrl]) unless
/// `SHOREBIRD_HOSTED_URL` or `AUTH_SERVICE_URL` name another server.
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

  /// The lockfile that pins this project's iOS native dependencies, or null
  /// if there is none. See [nativeDependencyLockFile].
  File? get iosNativeDependencyLockFile => nativeDependencyLockFile('ios');

  /// The hash of [iosNativeDependencyLockFile], or null if there is none.
  String? get iosNativeDependencyLockHash =>
      _hashFile(iosNativeDependencyLockFile);

  /// The lockfile that pins this project's macOS native dependencies, or null
  /// if there is none. See [nativeDependencyLockFile].
  File? get macosNativeDependencyLockFile => nativeDependencyLockFile('macos');

  /// The hash of [macosNativeDependencyLockFile], or null if there is none.
  String? get macosNativeDependencyLockHash =>
      _hashFile(macosNativeDependencyLockFile);

  /// The lockfile that pins the native dependencies of the Apple app in
  /// [platformDirectory] (`ios` or `macos`): its Podfile.lock if it uses
  /// CocoaPods, otherwise, for an app on Swift Package Manager alone, the
  /// Package.resolved in Runner.xcworkspace. Null if it has neither.
  File? nativeDependencyLockFile(String platformDirectory) {
    final platformRoot = p.join(
      getFlutterProjectRoot()!.path,
      platformDirectory,
    );
    final candidates = [
      File(p.join(platformRoot, 'Podfile.lock')),
      File(
        p.join(
          platformRoot,
          'Runner.xcworkspace',
          'xcshareddata',
          'swiftpm',
          'Package.resolved',
        ),
      ),
    ];
    return candidates.firstWhereOrNull((file) => file.existsSync());
  }

  String? _hashFile(File? file) {
    if (file == null) return null;
    final bytes = file.readAsBytesSync();
    if (p.basename(file.path) == 'Package.resolved') {
      final pins = _packageResolvedPins(utf8.decode(bytes));
      if (pins != null) return sha256.convert(utf8.encode(pins)).toString();
    }
    return sha256.convert(bytes).toString();
  }

  /// The pinned packages in a Package.resolved, sorted and encoded so that
  /// only the resolved versions affect the hash. Xcode also writes fields
  /// that change without any native dependency changing (`originHash`,
  /// which tracks the manifests, and the file format `version`, which
  /// differs between Xcode versions). Null if [contents] can't be parsed.
  static String? _packageResolvedPins(String contents) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException {
      return null;
    }
    final pins = switch (json) {
      {'pins': final List<dynamic> pins} => pins,
      // Format version 1 nests the pins under "object".
      {'object': {'pins': final List<dynamic> pins}} => pins,
      _ => null,
    };
    if (pins == null) return null;
    final encoded = pins.map((pin) => jsonEncode(_sortKeys(pin))).toList()
      ..sort();
    return encoded.join('\n');
  }

  static Object? _sortKeys(Object? value) => switch (value) {
    final Map<String, dynamic> map => {
      for (final key in map.keys.sorted()) key: _sortKeys(map[key]),
    },
    final List<dynamic> list => list.map(_sortKeys).toList(),
    _ => value,
  };

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
  /// `AUTH_SERVICE_URL` environment variable when it is set, otherwise
  /// [devAuthServiceUrl] with `--dev` (see [isDevMode]), otherwise
  /// [defaultAuthServiceUrl].
  Uri get authServiceUri => Uri.parse(
    platform.environment['AUTH_SERVICE_URL'] ??
        (isDevMode ? devAuthServiceUrl : defaultAuthServiceUrl),
  );

  /// The base URL for the Shorebird code push server that overrides the default
  /// used by [CodePushClient]: the `SHOREBIRD_HOSTED_URL` environment
  /// variable when it is set, otherwise [devHostedUrl] with `--dev` (see
  /// [isDevMode]), otherwise the `base_url` in shorebird.yaml. If none is
  /// provided, [CodePushClient] will use its default.
  Uri? get hostedUri {
    try {
      final baseUrl =
          platform.environment['SHOREBIRD_HOSTED_URL'] ??
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
  /// platform. This implementation is intended to behave similar to the Flutter
  /// tool's:
  /// https://github.com/flutter/flutter/blob/0c10e1ca54ae74043909059e2ff56bf5dd0c3d23/packages/flutter_tools/lib/src/base/bot_detector.dart#L48-L69
  bool get isRunningOnCI =>
      platform.environment['BOT'] == 'true'
      // https://docs.travis-ci.com/user/environment-variables/#Default-Environment-Variables
      ||
      platform.environment['TRAVIS'] == 'true' ||
      platform.environment['CONTINUOUS_INTEGRATION'] == 'true' ||
      platform.environment.containsKey('CI') // Travis and AppVeyor
      // https://www.appveyor.com/docs/environment-variables/
      ||
      platform.environment.containsKey('APPVEYOR')
      // https://cirrus-ci.org/guide/writing-tasks/#environment-variables
      ||
      platform.environment.containsKey('CIRRUS_CI')
      // https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-env-vars.html
      ||
      (platform.environment.containsKey('AWS_REGION') &&
          platform.environment.containsKey('CODEBUILD_INITIATOR'))
      // https://wiki.jenkins.io/display/JENKINS/Building+a+software+project#Buildingasoftwareproject-belowJenkinsSetEnvironmentVariables
      ||
      platform.environment.containsKey('JENKINS_URL')
      // https://help.github.com/en/actions/configuring-and-managing-workflows/using-environment-variables#default-environment-variables
      ||
      platform.environment.containsKey('GITHUB_ACTIONS')
      // https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml
      ||
      platform.environment.containsKey('TF_BUILD');
}
