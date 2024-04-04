import 'dart:io' hide Platform;

import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// A reference to a [ShorebirdEnv] instance.
final shorebirdEnvRef = create(ShorebirdEnv.new);

/// The [ShorebirdEnv] instance available in the current zone.
ShorebirdEnv get shorebirdEnv => read(shorebirdEnvRef);

/// {@template shorebird_env}
/// A class that provides access to shorebird environment metadata.
/// {@endtemplate}
class ShorebirdEnv {
  /// {@macro shorebird_env}
  const ShorebirdEnv({String? flutterRevisionOverride})
      : _flutterRevisionOverride = flutterRevisionOverride;

  ShorebirdEnv copyWith({String? flutterRevisionOverride}) => ShorebirdEnv(
        flutterRevisionOverride:
            flutterRevisionOverride ?? _flutterRevisionOverride,
      );

  final String? _flutterRevisionOverride;

  /// The root directory of the Shorebird install.
  ///
  /// Assumes we are running from $ROOT/bin/cache.
  Directory get shorebirdRoot {
    return File(platform.script.toFilePath()).parent.parent.parent;
  }

  String get shorebirdEngineRevision {
    return File(
      p.join(
        flutterDirectory.path,
        'bin',
        'internal',
        'engine.version',
      ),
    ).readAsStringSync().trim();
  }

  set flutterRevision(String revision) {
    if (revision == flutterRevision) return;
    File(
      p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'),
    ).writeAsStringSync(revision);
    final snapshot = File(
      p.join(shorebirdRoot.path, 'bin', 'cache', 'shorebird.snapshot'),
    );
    if (snapshot.existsSync()) snapshot.deleteSync();
  }

  String get flutterRevision {
    return _flutterRevisionOverride ??
        File(
          p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'),
        ).readAsStringSync().trim();
  }

  /// The root of the Shorebird-vended Flutter git checkout.
  Directory get flutterDirectory {
    return Directory(
      p.join(
        shorebirdRoot.path,
        'bin',
        'cache',
        'flutter',
        flutterRevision,
      ),
    );
  }

  /// The Shorebird-vended Flutter binary.
  File get flutterBinaryFile {
    return File(p.join(flutterDirectory.path, 'bin', 'flutter'));
  }

  /// The Shorebird-vended Dart binary.
  File get dartBinaryFile {
    return File(p.join(flutterDirectory.path, 'bin', 'dart'));
  }

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
    final yaml = getPubspecYamlFile(cwd: root).readAsStringSync();
    try {
      return Pubspec.parse(yaml);
    } catch (_) {
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

  /// The base URL for the Shorebird code push server that overrides the default
  /// used by [CodePushClient]. If none is provided, [CodePushClient] will use
  /// its default.
  Uri? get hostedUri {
    try {
      final baseUrl = platform.environment['SHOREBIRD_HOSTED_URL'] ??
          getShorebirdYaml()?.baseUrl;
      return baseUrl == null ? null : Uri.tryParse(baseUrl);
    } catch (_) {
      return null;
    }
  }

  /// Whether the CLI can accept user input via stdin.
  bool get canAcceptUserInput => stdin.hasTerminal && !isRunningOnCI;

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
