import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/git.dart';
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

    // Clone the Shorebird Flutter repo into the target directory.
    await git.clone(
      url: flutterGitUrl,
      outputDirectory: targetDirectory.path,
      args: [
        '--filter=tree:0',
        '--no-checkout',
      ],
    );

    // Checkout the correct revision.
    await git.checkout(
      directory: targetDirectory.path,
      revision: revision,
    );
  }
}
