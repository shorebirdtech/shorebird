import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';

/// A reference to a [OperatingSystemInterface] instance.
final osRef = create(() => OperatingSystemInterface.instance);

/// The [OperatingSystemInterface] instance available in the current zone.
OperatingSystemInterface get os => read(osRef);

abstract class OperatingSystemInterface {
  /// Returns the first instance of [executableName] found on the PATH.
  ///
  /// This is the equivalent of the `which` command on Linux and macOS and
  /// `where.exe` on Windows.
  Future<String?> which(String executableName);

  static OperatingSystemInterface get instance {
    if (Platform.isWindows) {
      return _WindowsOperatingSystemInterface();
    } else if (Platform.isMacOS || Platform.isLinux) {
      return _PosixOperatingSystemInterface();
    }

    throw UnsupportedError(
      'Unsupported operating system: ${Platform.operatingSystem}',
    );
  }
}

class _PosixOperatingSystemInterface implements OperatingSystemInterface {
  @override
  Future<String?> which(String executableName) async {
    final result = await process.run('which', [executableName]);
    if (result.exitCode != ExitCode.success.code) {
      return null;
    }

    print('which stdout is ${result.stdout}');

    return result.stdout as String?;
  }
}

class _WindowsOperatingSystemInterface implements OperatingSystemInterface {
  @override
  Future<String?> which(String executableName) async {
    final result = await process.run('where.exe', [executableName]);
    if (result.exitCode != ExitCode.success.code) {
      return null;
    }

    print('where.exe stdout is ${result.stdout}');

    return null;
  }
}
