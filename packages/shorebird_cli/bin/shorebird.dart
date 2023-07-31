import 'dart:io';

import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/adb.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/bundletool.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/gradlew.dart';
import 'package:shorebird_cli/src/ios_deploy.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_version_manager.dart';
import 'package:shorebird_cli/src/xcodebuild.dart';

Future<void> main(List<String> args) async {
  await _flushThenExit(
    await runScoped(
      () async => ShorebirdCliCommandRunner().run(args),
      values: {
        adbRef,
        androidSdkRef,
        androidStudioRef,
        authRef,
        bundletoolRef,
        cacheRef,
        codePushClientWrapperRef,
        doctorRef,
        engineConfigRef,
        gradlewRef,
        iosDeployRef,
        javaRef,
        loggerRef,
        platformRef,
        processRef,
        shorebirdVersionManagerRef,
        xcodeBuildRef,
      },
    ),
  );
}

/// Flushes the stdout and stderr streams, then exits the program with the given
/// status code.
///
/// This returns a Future that will never complete, since the program will have
/// exited already. This is useful to prevent Future chains from proceeding
/// after you've decided to exit.
Future<void> _flushThenExit(int status) {
  return Future.wait<void>([stdout.close(), stderr.close()])
      .then<void>((_) => exit(status));
}
