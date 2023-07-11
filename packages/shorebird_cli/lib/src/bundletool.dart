import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/process.dart';

// A reference to a [Bundletool] instance.
final bundletoolRef = create(Bundletool.new);

// The [Bundletool] instance available in the current zone.
Bundletool get bundletool => read(bundletoolRef);

class Bundletool {
  static const jar = 'bundletool.jar';

  Future<ShorebirdProcessResult> _exec(String command) async {
    await cache.updateAll();
    final bundletool = p.join(cache.getArtifactDirectory(jar).path, jar);
    final javaHome = java.home();
    final javaExecutable = java.executable() ?? 'java';

    return process.run(
      javaExecutable,
      ['-jar', bundletool, ...command.split(' ')],
      environment: {
        if (javaHome != null) 'JAVA_HOME': javaHome,
      },
    );
  }

  Future<String> getVersionName(String appBundlePath) async {
    final result = await _exec(
      'dump manifest --bundle $appBundlePath --xpath /manifest/@android:versionName',
    );

    if (result.exitCode != 0) {
      throw Exception(
        '''Failed to extract version name from app bundle: ${result.stderr}''',
      );
    }

    return (result.stdout as String).trim();
  }

  Future<String> getVersionCode(String appBundlePath) async {
    final result = await _exec(
      'dump manifest --bundle $appBundlePath --xpath /manifest/@android:versionCode',
    );

    if (result.exitCode != 0) {
      throw Exception(
        '''Failed to extract version code from app bundle: ${result.stderr}''',
      );
    }

    return (result.stdout as String).trim();
  }
}
