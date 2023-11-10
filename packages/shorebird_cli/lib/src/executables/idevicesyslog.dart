import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

class IDeviceSysLog {
  static Directory get libimobiledeviceDirectory => Directory(
        p.join(
          shorebirdEnv.flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'libimobiledevice',
        ),
      );

  static File get idevicesyslogExecutable => File(
        p.join(libimobiledeviceDirectory.path, 'idevicesyslog'),
      );

  Future<Process> startLogger(String deviceId) async {
    final dyldPathEntry =
        '/Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/e744c831b8355bcb9f3b541d42431d9145eea677/bin/cache/artifacts/libimobiledevice:/Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/e744c831b8355bcb9f3b541d42431d9145eea677/bin/cache/artifacts/usbmuxd:/Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/e744c831b8355bcb9f3b541d42431d9145eea677/bin/cache/artifacts/libplist:/Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/e744c831b8355bcb9f3b541d42431d9145eea677/bin/cache/artifacts/openssl:/Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/e744c831b8355bcb9f3b541d42431d9145eea677/bin/cache/artifacts/ios-deploy';
    print(
      'starting logger process with env DYLD_LIBRARY_PATH=$dyldPathEntry',
    );
    //  [
    //   libimobiledeviceDirectory.path,
    //   p.join(
    //     shorebirdEnv.flutterDirectory.path,
    //     'bin',
    //     'cache',
    //     'artifacts',
    //     'openssl',
    //   ),
    // ].join(':');
    return process.start(
      idevicesyslogExecutable.path,
      ['-u', deviceId],
      environment: {
        'DYLD_LIBRARY_PATH': dyldPathEntry,
      },
    );
  }
}
