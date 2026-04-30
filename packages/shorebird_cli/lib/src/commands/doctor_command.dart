import 'dart:io';

import 'package:cli_io/cli_io.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/network_checker.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';

/// {@template doctor_command}
/// `shorebird doctor`
/// A command that checks for potential issues with the current shorebird
/// environment.
/// {@endtemplate}
class DoctorCommand extends ShorebirdCommand {
  /// {@macro doctor_command}
  DoctorCommand() {
    argParser
      ..addFlag(
        'fix',
        abbr: 'f',
        help: 'Fix issues where possible.',
        negatable: false,
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enable verbose output.',
        negatable: false,
      );
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Show information about the installed tooling.';

  @override
  Future<int> run() async {
    if (isJsonMode) return _runJson();

    final verbose = results['verbose'] == true;
    final shouldFix = results['fix'] == true;
    final flutterVersion = await _tryGetFlutterVersion();
    final output = StringBuffer();
    final shorebirdFlutterPrefix = StringBuffer('Flutter');

    if (flutterVersion != null) {
      shorebirdFlutterPrefix.write(' $flutterVersion');
    }
    output.writeln('''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
$shorebirdFlutterPrefix • revision ${shorebirdEnv.flutterRevision}
Engine • revision ${shorebirdEnv.shorebirdEngineRevision}''');

    if (verbose) {
      final notDetected = red.wrap('not detected');
      var javaVersion = notDetected;

      final javaExe = java.executable;
      if (javaExe != null) {
        final result = java.version;
        if (result != null) {
          javaVersion = result
              .split(Platform.lineTerminator)
              // Adds empty space to the version will be padded with the
              // JAVA_VERSION label.
              .join('${Platform.lineTerminator}                  ');
        }
      }

      String? gradlewVersion;
      if (gradlew.exists(Directory.current.path)) {
        gradlewVersion = await gradlew.version(Directory.current.path);
      }

      output.writeln('''

Logs: ${shorebirdEnv.logsDirectory.path}
Android Toolchain
  • Android Studio: ${androidStudio.path ?? notDetected}
  • Android SDK: ${androidSdk.path ?? notDetected}
  • ADB: ${androidSdk.adbPath ?? notDetected}
  • JAVA_HOME: ${java.home ?? notDetected}
  • JAVA_EXECUTABLE: ${javaExe ?? notDetected}
  • JAVA_VERSION: $javaVersion
  • Gradle: ${gradlewVersion ?? notDetected}''');
    }

    logger
      ..info(output.toString())
      ..info('URL Reachability');
    await networkChecker.checkReachability();
    logger.info('');

    if (verbose) {
      logger.info('Network Speed');
      final uploadProgress = logger.progress('Measuring GCP upload speed');

      try {
        final uploadSpeed = await networkChecker.performGCPUploadSpeedTest();
        uploadProgress.complete(
          'GCP Upload Speed: ${uploadSpeed.toStringAsFixed(2)} MB/s',
        );
      } on NetworkCheckerException catch (error) {
        uploadProgress.fail('GCP upload speed test failed: ${error.message}');
      } on Exception catch (error) {
        uploadProgress.fail('GCP upload speed test failed: $error');
      }

      final downloadProgress = logger.progress('Measuring GCP download speed');

      try {
        final downloadSpeed = await networkChecker
            .performGCPDownloadSpeedTest();
        downloadProgress.complete(
          'GCP Download Speed: ${downloadSpeed.toStringAsFixed(2)} MB/s',
        );
      } on NetworkCheckerException catch (error) {
        downloadProgress.fail(
          'GCP download speed test failed: ${error.message}',
        );
      } on Exception catch (error) {
        downloadProgress.fail('GCP download speed test failed: $error');
      }
      logger.info('');
    }

    await doctor.runValidators(
      doctor.initAndDoctorValidators,
      applyFixes: shouldFix,
    );

    return ExitCode.success.code;
  }

  Future<int> _runJson() async {
    final flutterVersion = await _tryGetFlutterVersion();

    String? javaVersion;
    if (java.executable != null) {
      javaVersion = java.version;
    }

    String? gradleVersion;
    if (gradlew.exists(Directory.current.path)) {
      try {
        gradleVersion = await gradlew.version(Directory.current.path);
      } on Exception {
        // Gradle version detection can fail — report as null.
      }
    }

    // Direct HTTP checks — avoids networkChecker.checkReachability which
    // logs to the terminal instead of returning structured data.
    final networkResults = await Future.wait(
      NetworkChecker.urlsToCheck.map((url) async {
        try {
          await httpClient.get(url);
          return {'url': '$url', 'reachable': true};
        } on Exception {
          return {'url': '$url', 'reachable': false};
        }
      }),
    );

    // Direct validator calls — avoids doctor.runValidators which logs
    // to the terminal instead of returning structured data.
    final validatorResults = <Map<String, dynamic>>[];
    for (final validator in doctor.initAndDoctorValidators) {
      if (!validator.canRunInCurrentContext()) continue;
      final issues = await validator.validate();
      validatorResults.add({
        'name': validator.description,
        'ok': !issues.any(
          (i) => i.severity == ValidationIssueSeverity.error,
        ),
        'issues': issues
            .map(
              (i) => {
                'severity': i.severity.name,
                'message': i.message,
              },
            )
            .toList(),
      });
    }

    Map<String, dynamic>? speedTest;
    if (results['verbose'] == true) {
      double? uploadMbPerSec;
      double? downloadMbPerSec;
      try {
        uploadMbPerSec = await networkChecker.performGCPUploadSpeedTest();
      } on Exception {
        // Report as null on failure.
      }
      try {
        downloadMbPerSec = await networkChecker.performGCPDownloadSpeedTest();
      } on Exception {
        // Report as null on failure.
      }
      speedTest = {
        'upload_megabytes_per_sec': uploadMbPerSec,
        'download_megabytes_per_sec': downloadMbPerSec,
      };
    }

    emitJsonSuccess({
      'shorebird_version': packageVersion,
      'flutter_version': flutterVersion,
      'flutter_revision': shorebirdEnv.flutterRevision,
      'engine_revision': shorebirdEnv.shorebirdEngineRevision,
      'android_toolchain': {
        'android_studio': androidStudio.path,
        'android_sdk': androidSdk.path,
        'adb': androidSdk.adbPath,
        'java_home': java.home,
        'java_version': javaVersion,
        'gradle_version': gradleVersion,
      },
      'network': networkResults,
      if (speedTest != null) 'speed_test': speedTest,
      'validators': validatorResults,
    });
    return ExitCode.success.code;
  }

  Future<String?> _tryGetFlutterVersion() async {
    try {
      return await shorebirdFlutter.getVersionString();
    } on Exception catch (error) {
      logger.detail('Unable to determine Flutter version.\n$error');
      return null;
    }
  }
}
