import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';

/// A reference to a [OperatingSystemInterface] instance.
final osRef = create(OperatingSystemInterface.new);

/// The [OperatingSystemInterface] instance available in the current zone.
OperatingSystemInterface get os => read(osRef);

/// {@template operating_system_interface}
/// A wrapper around operating system specific functionality.
/// {@endtemplate}
abstract class OperatingSystemInterface {
  /// {@macro operating_system_interface}
  factory OperatingSystemInterface() {
    if (platform.isWindows) {
      return _WindowsOperatingSystemInterface();
    } else if (platform.isMacOS || platform.isLinux) {
      return _PosixOperatingSystemInterface();
    }

    throw UnsupportedError(
      'Unsupported operating system: ${Platform.operatingSystem}',
    );
  }

  /// Returns the first instance of [executableName] found on the PATH.
  ///
  /// This is the equivalent of the `which` command on Linux and macOS and
  /// `where.exe` on Windows.
  String? which(String executableName);
}

class _PosixOperatingSystemInterface implements OperatingSystemInterface {
  @override
  String? which(String executableName) {
    final result = process.runSync('which', [executableName]);
    if (result.exitCode != ExitCode.success.code) {
      return null;
    }

    return result.stdout as String?;
  }
}

class _WindowsOperatingSystemInterface implements OperatingSystemInterface {
  @override
  String? which(String executableName) {
    final result = process.runSync('where.exe', [executableName]);
    if (result.exitCode != ExitCode.success.code) {
      return null;
    }

    // By default, where.exe will list all matching executables on PATH. We want
    // to return the first one.
    return (result.stdout as String).split('\n').firstOrNull;
  }
}
