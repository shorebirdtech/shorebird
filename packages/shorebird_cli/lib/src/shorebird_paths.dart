import 'dart:io';

import 'package:path/path.dart' as p;

abstract class ShorebirdPaths {
  /// The root directory of the Shorebird install.
  ///
  /// Assumes we are running from $ROOT/bin/cache.
  static Directory shorebirdRoot =
      File(Platform.script.toFilePath()).parent.parent.parent;

  /// Path to the Shorebird-vended Flutter binary.
  static String get flutterBinaryPath => p.join(
        shorebirdRoot.path,
        'bin',
        'cache',
        'flutter',
        'bin',
        'flutter',
      );
}
