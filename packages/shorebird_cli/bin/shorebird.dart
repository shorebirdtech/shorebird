import 'dart:io';

import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';

Future<void> main(List<String> args) async {
  await _flushThenExit(
    await runScoped(
      () async => ShorebirdCliCommandRunner().run(args),
      values: {
        adbRef,
        androidSdkRef,
        androidStudioRef,
        artifactManagerRef,
        authRef,
        bundletoolRef,
        cacheRef,
        codePushClientWrapperRef,
        devicectlRef,
        doctorRef,
        engineConfigRef,
        gitRef,
        gradlewRef,
        idevicesyslogRef,
        iosDeployRef,
        javaRef,
        loggerRef,
        osInterfaceRef,
        patchDiffCheckerRef,
        platformRef,
        processRef,
        shorebirdEnvRef,
        shorebirdFlutterRef,
        shorebirdValidatorRef,
        shorebirdVersionRef,
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
