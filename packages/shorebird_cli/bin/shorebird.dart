import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/pubspec_editor.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
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
        aotToolsRef,
        artifactBuilderRef,
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
        httpClientRef,
        idevicesyslogRef,
        iosDeployRef,
        iosRef,
        javaRef,
        loggerRef,
        osInterfaceRef,
        patchExecutableRef,
        patchDiffCheckerRef,
        platformRef,
        processRef,
        pubspecEditorRef,
        shorebirdAndroidArtifactsRef,
        shorebirdArtifactsRef,
        shorebirdEnvRef,
        shorebirdFlutterRef,
        shorebirdToolsRef,
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
