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

  /// The root of the Shorebird-vended Flutter git checkout.
  static Directory get flutterDirectory => Directory(
        p.join(
          shorebirdRoot.path,
          'bin',
          'cache',
          'flutter',
        ),
      );

  /// The Shorebird cache directory.
  static Directory get shorebirdCacheDirectory => Directory(
        p.join(shorebirdRoot.path, 'bin', 'cache'),
      );

  /// The Shorebird-vended Flutter binary.
  static File get flutterBinaryFile => File(
        p.join(
          flutterDirectory.path,
          'bin',
          'flutter',
        ),
      );
}
