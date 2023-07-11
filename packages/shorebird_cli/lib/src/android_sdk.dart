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

class AndroidSdk {
  String? get path {
    String? androidHomeDir;
    if (platform.environment.containsKey(kAndroidHome)) {
      androidHomeDir = platform.environment[kAndroidHome];
    } else if (platform.environment.containsKey(kAndroidSdkRoot)) {
      androidHomeDir = platform.environment[kAndroidSdkRoot];
    } else if (platform.isLinux) {
      final home = platform.environment['HOME'] ?? '~';
      androidHomeDir = p.join(home, 'Android', 'Sdk');
    } else if (platform.isMacOS) {
      final home = platform.environment['HOME'] ?? '~';
      androidHomeDir = p.join(home, 'Library', 'Android', 'sdk');
    } else if (platform.isWindows) {
      final home = platform.environment['HOME'] ?? '~';
      androidHomeDir = p.join(home, 'AppData', 'Local', 'Android', 'sdk');
    }

    return androidHomeDir;
  }

  late final adbPath = getPlatformToolsPath(
    platform.isWindows ? 'adb.exe' : 'adb',
  );

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
