import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [ShorebirdFlutterManager] instance.
final shorebirdFlutterManagerRef = create(ShorebirdFlutterManager.new);

/// The [ShorebirdFlutterManager] instance available in the current zone.
ShorebirdFlutterManager get shorebirdFlutterManager {
  return read(shorebirdFlutterManagerRef);
}

/// {@template shorebird_flutter_manager}
/// Helps manage the Flutter installation used by Shorebird.
/// {@endtemplate}
class ShorebirdFlutterManager {
  /// {@macro shorebird_flutter_manager}
  const ShorebirdFlutterManager();

  static const String flutterGitUrl =
      'https://github.com/shorebirdtech/flutter.git';

  Future<void> installRevision({required String revision}) async {
    final targetDirectory = Directory(
      p.join(shorebirdEnv.flutterDirectory.parent.path, revision),
    );
    if (targetDirectory.existsSync()) return;
    const executable = 'git';

    // Clone the Shorebird Flutter repo into the target directory.
    final cloneArgs = [
      'clone',
      '--filter=tree:0',
      flutterGitUrl,
      '--no-checkout',
      targetDirectory.path,
    ];
    final cloneResult = await process.run(
      executable,
      cloneArgs,
      runInShell: true,
    );
    if (cloneResult.exitCode != 0) {
      throw ProcessException(
        executable,
        cloneArgs,
        '${cloneResult.stderr}',
        cloneResult.exitCode,
      );
    }

    // Checkout the correct revision.
    final checkoutArgs = [
      '-C',
      targetDirectory.path,
      '-c',
      'advice.detachedHead=false',
      'checkout',
      revision,
    ];
    final checkoutResult = await process.run(
      executable,
      checkoutArgs,
      runInShell: true,
    );
    if (checkoutResult.exitCode != 0) {
      throw ProcessException(
        executable,
        checkoutArgs,
        '${checkoutResult.stderr}',
        checkoutResult.exitCode,
      );
    }
  }
}
