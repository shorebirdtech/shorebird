import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [IOSDeploy] instance.
final iosDeployRef = create(IOSDeploy.new);

/// The [IOSDeploy] instance available in the current zone.
IOSDeploy get iosDeploy => read(iosDeployRef);

/// lldb debugger state.
enum _DebuggerState {
  detached,
  launching,
  attached,
}

/// Wrapper around the `ios-deploy` command cached by the Flutter tool.
/// https://github.com/ios-control/ios-deploy
class IOSDeploy {
  IOSDeploy({ProcessSignal? sigint}) : _sigint = sigint ?? ProcessSignal.sigint;

  final ProcessSignal _sigint;

  @visibleForTesting
  static File get iosDeployExecutable => File(
        p.join(
          shorebirdEnv.flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'ios-deploy',
          'ios-deploy',
        ),
      );

  static bool get _isInstalled => iosDeployExecutable.existsSync();

  // (lldb)    platform select remote-'ios' --sysroot
  // This regex is to get the configurable lldb prompt.
  // By default this prompt will be "lldb".
  static final _lldbPlatformSelect =
      RegExp(r"\s*platform select remote-'ios' --sysroot");

  // (lldb)     run
  static final _lldbProcessExit = RegExp(r'Process \d* exited with status =');

  // (lldb) Process 1234 stopped
  static final _lldbProcessStopped = RegExp(r'Process \d* stopped');

  // (lldb) Process 1234 detached
  static final _lldbProcessDetached = RegExp(r'Process \d* detached');

  // (lldb) Process 1234 resuming
  static final _lldbProcessResuming = RegExp(r'Process \d+ resuming');

  // Send signal to stop (pause) the app. Used before a backtrace dump.
  static const String _signalStop = 'process signal SIGSTOP';

  // Print backtrace for all threads while app is stopped.
  static const String _backTraceAll = 'thread backtrace all';

  // No provision profile errors.
  static const noProvisioningProfileErrorOne = 'Error 0xe8008015';
  static const noProvisioningProfileErrorTwo = 'Error 0xe8000067';

  // Device locked errors.
  static const deviceLockedError = 'e80000e2';
  static const deviceLockedErrorMessage =
      'the device was not, or could not be, unlocked';

  // Unknown launch error.
  static const unknownAppLaunchError = 'Error 0xe8000022';

  // Message when there is an unknown error.
  static const unknownErrorFixInstructions = '''
═══════════════════════════════════════════════════════════════════════════════════
Error launching app. Try launching from within Xcode via:
    open ios/Runner.xcworkspace

Your Xcode version may be too old for your iOS version.
═══════════════════════════════════════════════════════════════════════════════════''';

  // Message when the device is locked.
  static const deviceLockedFixInstructions = '''
═══════════════════════════════════════════════════════════════════════════════════
Your device is locked. Unlock your device first before running.
═══════════════════════════════════════════════════════════════════════════════════''';

  // Message when there is no development team selected.
  static const developmentTeamFixInstructions = '''
  1- Open the Flutter project's Xcode target with
       open ios/Runner.xcworkspace
  2- Select the 'Runner' project in the navigator then the 'Runner' target
     in the project settings
  3- Make sure a 'Development Team' is selected under Signing & Capabilities > Team.\u0020
     You may need to:
         - Log in with your Apple ID in Xcode first
         - Ensure you have a valid unique Bundle ID
         - Register your device with your Apple Developer Account
         - Let Xcode automatically provision a profile for your app
  4- Build or run your project again''';

  /// Message when there is no provisioning profile.
  static const noProvisioningProfileInstructions = '''
════════════════════════════════════════════════════════════════════════════════
No Provisioning Profile was found for your project's Bundle Identifier or your\u0020
device. You can create a new Provisioning Profile for your project in Xcode for\u0020
your team by:
$developmentTeamFixInstructions

It's also possible that a previously installed app with the same Bundle\u0020
Identifier was signed with a different certificate.

For more information, please visit:
  https://flutter.dev/docs/get-started/install/macos#deploy-to-ios-devices

Or run on an iOS simulator without code signing
════════════════════════════════════════════════════════════════════════════════''';

  /// Installs the .app file at [bundlePath]
  /// to the device identified by [deviceId] and attaches the debugger.
  /// Returns the process exit code.
  ///
  /// Uses ios-deploy and returns the exit code.
  /// `ios-deploy --id [deviceId] --debug --bundle [bundlePath]`
  Future<int> installAndLaunchApp({
    required String bundlePath,
    String? deviceId,
  }) async {
    // Ensure ios-deploy executable is installed.
    await installIfNeeded();

    var debuggerState = _DebuggerState.detached;

    // (lldb)     run
    var lldbRun = RegExp(r'\(lldb\)\s*run');

    final launchProgress = logger.progress('Starting app');
    late final Process launchProcess;

    // If the user presses Ctrl-C, kill the ios-deploy process.
    _sigint.watch().listen((signal) {
      // If the debugger is attached, send the signal to the app process.
      if (debuggerState.isAttached) launchProcess.stdin.writeln(_signalStop);
      launchProcess.kill();
    });

    try {
      launchProcess = await process.start(
        iosDeployExecutable.path,
        [
          '--debug',
          if (deviceId != null) ...['--id', deviceId],
          '-r', // uninstall the app before reinstalling and clear app data
          '--bundle',
          bundlePath,
        ],
      );

      void detach() {
        if (debuggerState.isNotAttached) return;
        launchProcess.stdin.writeln('process detach');
      }

      bool kill() => launchProcess.kill();

      String? previousLine;

      void onStdout(String line) {
        detectFailures(line, logger);

        // Detect the lldb prompt since it can be configured by the end user.
        if (_lldbPlatformSelect.hasMatch(line)) {
          final platformSelect = _lldbPlatformSelect.stringMatch(line) ?? '';
          if (platformSelect.isEmpty) {
            return;
          }
          final promptEndIndex = line.indexOf(platformSelect);
          if (promptEndIndex == -1) {
            return;
          }
          final prompt = line.substring(0, promptEndIndex);
          lldbRun = RegExp(RegExp.escape(prompt) + r'\s*run');
          logger.detail(line);
          return;
        }

        // lldb is launching the debugger.
        // Example: (lldb)     run
        if (lldbRun.hasMatch(line)) {
          logger.detail(line);
          debuggerState = _DebuggerState.launching;
          return;
        }

        // The next line after "run" must either be "success"
        // or attaching the debugger was unsuccessful.
        if (debuggerState == _DebuggerState.launching) {
          logger.detail(line);
          final attachSuccess = line == 'success';
          debuggerState =
              attachSuccess ? _DebuggerState.attached : _DebuggerState.detached;
          launchProgress.complete(
            attachSuccess ? 'Started app' : 'Failed to start app',
          );
          return;
        }

        // The app has been stopped.
        if (line.contains('PROCESS_STOPPED') ||
            _lldbProcessStopped.hasMatch(line)) {
          logger.detail(line);
          launchProcess.stdin.writeln(_backTraceAll);
          detach();
          return;
        }

        // The app exited/crashed.
        if (line.contains('PROCESS_EXITED') ||
            _lldbProcessExit.hasMatch(line)) {
          logger.detail(line);
          kill();
          return;
        }

        // The debugger has detached from the app.
        if (_lldbProcessDetached.hasMatch(line)) {
          kill();
          return;
        }

        // The debugger is resuming.
        if (_lldbProcessResuming.hasMatch(line)) {
          logger.detail(line);
          debuggerState = _DebuggerState.attached;
          return;
        }

        // Format progress logs for the user while the debugger is attaching.
        if (debuggerState != _DebuggerState.attached) {
          if (line.contains('Copying') && line.endsWith('to device')) {
            final abbreviatedLine = line.replaceFirst('$bundlePath/', '');
            launchProgress.update(abbreviatedLine);
          } else if (line.startsWith(RegExp(r'\[\s+\d+\%\]'))) {
            launchProgress.update(line);
          } else {
            logger.detail(line);
          }
          return;
        }

        // Avoid logging empty lines.
        if ((previousLine?.isNotEmpty ?? false) && line.isEmpty) return;

        // Output logs after the debugger has attached.
        if (debuggerState == _DebuggerState.attached) {
          logger.info(line);
        }

        previousLine = line;
      }

      void onStderr(String line) {
        detectFailures(line, logger);
        logger.detail(line);
      }

      final stdoutSubscription =
          launchProcess.stdout.asLines().listen(onStdout);

      final stderrSubscription =
          launchProcess.stderr.asLines().listen(onStderr);

      final status = await launchProcess.exitCode;
      logger.detail('[ios-deploy] exited with code: $exitCode');
      debuggerState = _DebuggerState.detached;
      unawaited(stdoutSubscription.cancel());
      unawaited(stderrSubscription.cancel());
      return status;
    } catch (exception, stackTrace) {
      logger.detail('[ios-deploy] failed: $exception\n$stackTrace');
      debuggerState = _DebuggerState.detached;
      logger.err('[ios-deplay] failed: $exception');
      return ExitCode.software.code;
    }
  }

  /// Installs ios-deploy if it is not already installed.
  Future<void> installIfNeeded() async {
    if (_isInstalled) return;

    const executable = 'flutter';
    const arguments = ['precache', '--ios'];
    final progress = logger.progress('Installing ios-deploy');

    final result = await process.run(executable, arguments);

    if (result.exitCode != ExitCode.success.code) {
      progress.fail();
      throw ProcessException(executable, arguments, result.stderr as String);
    } else if (!_isInstalled) {
      const errorMessage = 'Failed to install ios-deploy.';
      progress.fail(errorMessage);
      throw Exception(errorMessage);
    }

    progress.complete();
  }
}

// Handles interpretting stdout line and logs errors accordingly.
// Always returns the original line.
@visibleForTesting
String detectFailures(String line, Logger logger) {
  final isMissingProvisioningProfile =
      line.contains(IOSDeploy.noProvisioningProfileErrorOne) ||
          line.contains(IOSDeploy.noProvisioningProfileErrorTwo);

  // No provisioning profile.
  if (isMissingProvisioningProfile) {
    logger.err(IOSDeploy.noProvisioningProfileInstructions);
    return line;
  }

  final isDeviceLocked = line.contains(IOSDeploy.deviceLockedError) ||
      line.contains(IOSDeploy.deviceLockedErrorMessage);

  if (isDeviceLocked) {
    logger.err(IOSDeploy.deviceLockedFixInstructions);
    return line;
  }

  final isUnknownAppLaunchError = line.contains(
    IOSDeploy.unknownAppLaunchError,
  );

  if (isUnknownAppLaunchError) {
    logger.err(IOSDeploy.unknownErrorFixInstructions);
    return line;
  }

  return line;
}

extension on _DebuggerState {
  bool get isAttached => this == _DebuggerState.attached;
  bool get isNotAttached => this != _DebuggerState.attached;
}

extension on Stream<List<int>> {
  Stream<String> asLines() {
    return transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter());
  }
}
