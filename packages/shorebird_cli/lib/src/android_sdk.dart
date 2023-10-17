import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
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
  ///
  /// This is based on the `flutter_tools` implementation. We check the
  /// following places in order for the Android SDK:
  ///   - ANDROID_HOME on the PATH
  ///   - ANDROID_SDK_ROOT on the PATH
  ///   - ~/Android/sdk (on Linux)
  ///   - ~/Library/Android/sdk (on macOS)
  ///   - $HOME\AppData\Local\Android\Sdk (on Windows)
  ///   - build-tools/$version/aapt
  ///   - platform-tools/adb
  String? get path {
    final candidatePaths = <String>[];
    if (platform.environment.containsKey(kAndroidHome)) {
      candidatePaths.add(platform.environment[kAndroidHome]!);
    }

    if (platform.environment.containsKey(kAndroidSdkRoot)) {
      candidatePaths.add(platform.environment[kAndroidSdkRoot]!);
    }

    final home = platform.isWindows
        ? platform.environment['USERPROFILE']
        : platform.environment['HOME'];

    if (home != null) {
      if (platform.isWindows) {
        candidatePaths.add(p.join(home, 'AppData', 'Local', 'Android', 'Sdk'));
      } else if (platform.isLinux) {
        candidatePaths.add(p.join(home, 'Android', 'Sdk'));
      } else if (platform.isMacOS) {
        candidatePaths.add(p.join(home, 'Library', 'Android', 'sdk'));
      }
    }

    final maybeAaptPath = osInterface.which('aapt');
    if (maybeAaptPath != null) {
      // Resolve path to aapt if it is a symlink.
      final resolvedAaptPath = File(maybeAaptPath).resolveSymbolicLinksSync();
      candidatePaths.add(File(resolvedAaptPath).parent.parent.parent.path);
    }

    final maybeAdbPath = osInterface.which('adb');
    if (maybeAdbPath != null) {
      // Resolve path to adb if it is a symlink.
      final resolvedAdbPath = File(maybeAdbPath).resolveSymbolicLinksSync();
      candidatePaths.add(File(resolvedAdbPath).parent.parent.path);
    }

    return candidatePaths.firstWhereOrNull(_isValidSdkPath);
  }

  bool _isValidSdkPath(String path) {
    final directory = Directory(path);
    final licensesDirectory = Directory(p.join(path, 'licenses'));
    final platformToolsDirectory = Directory(p.join(path, 'platform-tools'));
    return directory.existsSync() &&
        (licensesDirectory.existsSync() || platformToolsDirectory.existsSync());
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
