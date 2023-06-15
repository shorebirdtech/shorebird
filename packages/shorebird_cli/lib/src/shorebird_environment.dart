import 'dart:io' hide Platform;

import 'package:checked_yaml/checked_yaml.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/platform.dart';

abstract class ShorebirdEnvironment {
  /// Environment variables from [Platform.environment].
  static Map<String, String> get environment => platform.environment;

  /// The root directory of the Shorebird install.
  ///
  /// Assumes we are running from $ROOT/bin/cache.
  static Directory get shorebirdRoot =>
      File(platform.script.toFilePath()).parent.parent.parent;

  static String get shorebirdEngineRevision {
    return _shorebirdEngineRevision ??
        File(p.join(flutterDirectory.path, 'bin', 'internal', 'engine.version'))
            .readAsStringSync()
            .trim();
  }

  static String? _shorebirdEngineRevision;

  @visibleForTesting
  static set shorebirdEngineRevision(String revision) {
    _shorebirdEngineRevision = revision;
  }

  static String? _flutterRevision;

  @visibleForTesting
  static set flutterRevision(String revision) {
    _flutterRevision = revision;
  }

  static String get flutterRevision {
    return _flutterRevision ??
        File(
          p.join(shorebirdRoot.path, 'bin', 'internal', 'flutter.version'),
        ).readAsStringSync().trim();
  }

  /// The root of the Shorebird-vended Flutter git checkout.
  static Directory get flutterDirectory => Directory(
        p.join(
          shorebirdRoot.path,
          'bin',
          'cache',
          'flutter',
        ),
      );

  /// The Shorebird-vended Flutter binary.
  static File get flutterBinaryFile => File(
        p.join(
          flutterDirectory.path,
          'bin',
          'flutter',
        ),
      );

  static File get genSnapshotFile => File(
        p.join(
          flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'engine',
          'ios-release',
          'gen_snapshot_arm64',
        ),
      );

  static File getShorebirdYamlFile() {
    return File(p.join(Directory.current.path, 'shorebird.yaml'));
  }

  static ShorebirdYaml? getShorebirdYaml() {
    final file = getShorebirdYamlFile();
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return checkedYamlDecode(yaml, (m) => ShorebirdYaml.fromJson(m!));
  }

  static Pubspec? getPubspecYaml() {
    final file = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return Pubspec.parse(yaml);
  }

  static Uri? get hostedUri {
    try {
      final baseUrl = platform.environment['SHOREBIRD_HOSTED_URL'] ??
          getShorebirdYaml()?.baseUrl;
      return baseUrl == null ? null : Uri.tryParse(baseUrl);
    } catch (_) {
      return null;
    }
  }
}
