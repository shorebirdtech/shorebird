import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/args.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/java.dart';
import 'package:shorebird_cli/src/process.dart';

/// A reference to a [Bundletool] instance.
final bundletoolRef = create(Bundletool.new);

/// The [Bundletool] instance available in the current zone.
Bundletool get bundletool => read(bundletoolRef);

class Bundletool {
  static const jar = 'bundletool.jar';

  Future<ShorebirdProcessResult> _exec(List<String> command) async {
    await cache.updateAll();
    final bundletool = p.join(cache.getArtifactDirectory(jar).path, jar);
    final javaHome = java.home;
    final javaExecutable = java.executable ?? 'java';

    return process.run(
      javaExecutable,
      ['-jar', bundletool, ...command],
      environment: {
        if (javaHome != null) 'JAVA_HOME': javaHome,
      },
    );
  }

  /// Generate an APK set for all device configurations
  /// your app supports from an app bundle
  ///
  /// e.g. `bundletool build-apks --bundle=/MyApp/my_app.aab --output=/MyApp/my_app.apks`
  ///
  /// https://developer.android.com/tools/bundletool#generate_apks
  Future<void> buildApks({
    required String bundle,
    required String output,
  }) async {
    final result = await _exec(
      [
        'build-apks',
        '--${ArgsKey.overwrite}',
        '--${ArgsKey.bundle}=$bundle',
        '--${ArgsKey.output}=$output',
        '--${ArgsKey.mode}=universal',
      ],
    );
    if (result.exitCode != 0) {
      throw Exception('Failed to build apks: ${result.stderr}');
    }
  }

  /// Deploy your app from an APK set.
  ///
  /// e.g. `bundletool install-apks --apks=/MyApp/my_app.apks --allow-downgrade`
  ///
  /// https://developer.android.com/tools/bundletool#deploy_with_bundletool
  Future<void> installApks({
    required String apks,
    String? deviceId,
  }) async {
    final args = [
      'install-apks',
      '--${ArgsKey.apks}=$apks',
      '--${ArgsKey.allowDowngrade}',
      if (deviceId != null) '--${ArgsKey.deviceId}=$deviceId',
    ];
    final result = await _exec(args);
    if (result.exitCode != 0) {
      throw Exception('Failed to install apks: ${result.stderr}');
    }
  }

  /// Extract the package name from an app bundle.
  Future<String> getPackageName(String appBundlePath) async {
    final result = await _exec(
      [
        'dump',
        'manifest',
        '--${ArgsKey.bundle}=$appBundlePath',
        '--${ArgsKey.xpath}',
        '/manifest/@package',
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(
        '''Failed to extract package name from app bundle: ${result.stderr}''',
      );
    }

    return (result.stdout as String).trim();
  }

  /// Extract the version name from an app bundle.
  Future<String> getVersionName(String appBundlePath) async {
    final result = await _exec(
      [
        'dump',
        'manifest',
        '--${ArgsKey.bundle}=$appBundlePath',
        '--${ArgsKey.xpath}',
        '/manifest/@android:versionName',
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(
        '''Failed to extract version name from app bundle: ${result.stderr}''',
      );
    }

    return (result.stdout as String).trim();
  }

  /// Extract the version code from an app bundle.
  Future<String> getVersionCode(String appBundlePath) async {
    final result = await _exec(
      [
        'dump',
        'manifest',
        '--${ArgsKey.bundle}=$appBundlePath',
        '--${ArgsKey.xpath}',
        '/manifest/@android:versionCode',
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(
        '''Failed to extract version code from app bundle: ${result.stderr}''',
      );
    }

    return (result.stdout as String).trim();
  }
}
