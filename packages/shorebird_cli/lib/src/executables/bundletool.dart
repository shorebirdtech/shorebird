import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/java.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

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
    final androidSdkPath = androidSdk.path;

    return process.run(
      javaExecutable,
      ['-jar', bundletool, ...command],
      environment: {
        if (!androidSdkPath.isNullOrEmpty) 'ANDROID_HOME': androidSdkPath!,
        if (!javaHome.isNullOrEmpty) 'JAVA_HOME': javaHome!,
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
        '--overwrite',
        '--bundle=$bundle',
        '--output=$output',
        '--mode=universal',
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
      '--apks=$apks',
      '--allow-downgrade',
      if (deviceId != null) '--device-id=$deviceId',
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
        '--bundle=$appBundlePath',
        '--xpath',
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
        '--bundle=$appBundlePath',
        '--xpath',
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
        '--bundle=$appBundlePath',
        '--xpath',
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
