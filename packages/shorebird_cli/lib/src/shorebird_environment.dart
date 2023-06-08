import 'dart:io' hide Platform;

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';

abstract class ShorebirdEnvironment {
  @visibleForTesting
  static Platform platform = const LocalPlatform();

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
}
