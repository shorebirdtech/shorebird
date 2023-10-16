import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';

// https://developer.android.com/studio/command-line/variables.html#envar
const kAndroidHome = 'ANDROID_HOME';
const kAndroidSdkRoot = 'ANDROID_SDK_ROOT';

/// A reference to a [AndroidSdk] instance.
final androidSdkRef = create(AndroidSdk.new);

/// The [AndroidSdk] instance available in the current zone.
AndroidSdk get androidSdk => read(androidSdkRef);

/// A wrapper around Android SDK.
class AndroidSdk {
  /// The path to the Android SDK installation.
  String? get path {
    if (platform.environment.containsKey(kAndroidHome)) {
      return platform.environment[kAndroidHome];
    }

    if (platform.environment.containsKey(kAndroidSdkRoot)) {
      return platform.environment[kAndroidSdkRoot];
    }

    if (platform.isWindows) {
      final home = platform.environment['USERPROFILE'];
      if (home == null) return null;
      return p.join(home, 'AppData', 'Local', 'Android', 'sdk');
    }

    final home = platform.environment['HOME'];
    if (home == null) return null;

    // TODO: reference Flutter tool
    if (platform.isLinux) {
      // Don't assume this is right
      return p.join(home, 'Android', 'Sdk');
    }

    if (platform.isMacOS) {
      // Don't assume this is right
      return p.join(home, 'Library', 'Android', 'sdk');
    }

    return null;
  }

  /// The path to the `adb` executable.
  late final adbPath = getPlatformToolsPath(
    platform.isWindows ? 'adb.exe' : 'adb',
  );

  /// Returns a path to the given binary in the Android SDK platform tools.
  String? getPlatformToolsPath(String binary) {
    final androidSdkPath = path;
    if (androidSdkPath == null) return null;
    final candidatePaths = [
      p.join(androidSdkPath, 'cmdline-tools', binary),
      p.join(androidSdkPath, 'platform-tools', binary),
    ];

    return candidatePaths.firstWhereOrNull(
      (location) => File(location).existsSync(),
    );
  }
}
