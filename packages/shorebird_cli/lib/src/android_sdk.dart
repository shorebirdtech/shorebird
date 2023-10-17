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
    final candidatePathLookups = <String? Function()>[
      () => platform.environment[kAndroidHome],
      () => platform.environment[kAndroidSdkRoot],
      _defaultAndroidSdkPath,
      _androidSdkPathFromAapt,
      _androidSdkPathFromAdb,
    ];

    for (final lookup in candidatePathLookups) {
      final maybePath = lookup();
      if (maybePath != null && _isValidSdkPath(maybePath)) {
        return maybePath;
      }
    }

    return null;
  }

  /// For a path to be a valid Android SDK, it must exist and have either a
  /// licenses directory or a platform-tools directory. If the SDK only has a
  /// licenses directory, that indicates that the user has accepted the
  /// necessary Android licenses and that additional components can be
  /// downloaded later.
  bool _isValidSdkPath(String path) {
    final directory = Directory(path);
    final licensesDirectory = Directory(p.join(path, 'licenses'));
    final platformToolsDirectory = Directory(p.join(path, 'platform-tools'));
    return directory.existsSync() &&
        (licensesDirectory.existsSync() || platformToolsDirectory.existsSync());
  }

  /// Returns the default path to the Android SDK if a home directory is defined
  /// and we're on a recognized platform, or null otherwise.
  String? _defaultAndroidSdkPath() {
    final home = platform.isWindows
        ? platform.environment['USERPROFILE']
        : platform.environment['HOME'];
    if (home == null) {
      return null;
    }

    if (platform.isWindows) {
      return p.join(home, 'AppData', 'Local', 'Android', 'Sdk');
    } else if (platform.isLinux) {
      return p.join(home, 'Android', 'Sdk');
    } else if (platform.isMacOS) {
      return p.join(home, 'Library', 'Android', 'sdk');
    }

    return null;
  }

  /// If adb is on the user's path, return the Android SDK that contains it.
  ///
  /// In a valid Android SDK, adb is in the platform-tools directory.
  String? _androidSdkPathFromAdb() {
    final maybeAdbPath = osInterface.which('adb');
    if (maybeAdbPath == null) {
      return null;
    }

    // Resolve path to adb if it is a symlink.
    final resolvedAdbPath = File(maybeAdbPath).resolveSymbolicLinksSync();
    return File(resolvedAdbPath).parent.parent.path;
  }

  /// If aapt is on the user's path, return the Android SDK that contains it.
  ///
  /// In a valid Android SDK, aapt is in the build-tools/$version directory.
  String? _androidSdkPathFromAapt() {
    final maybeAaptPath = osInterface.which('aapt');
    if (maybeAaptPath == null) {
      return null;
    }

    // Resolve path to aapt if it is a symlink.
    final resolvedAaptPath = File(maybeAaptPath).resolveSymbolicLinksSync();
    return File(resolvedAaptPath).parent.parent.parent.path;
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
