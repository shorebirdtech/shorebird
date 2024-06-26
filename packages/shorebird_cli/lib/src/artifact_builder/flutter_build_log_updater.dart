import 'dart:collection';

import 'package:shorebird_cli/src/platform.dart';

/// A callback that is called when a new step is identified in the build
typedef BuildStepCallback = void Function(LogUpdaterStep step);

/// This enum describes the different steps that the log updater
/// identifies in the build process.
///
/// Not all of the steps apply to all platforms or to the situation of the
/// user's build (e.g. [downloadingGradleW] only applies to Android projects
/// in the first build).
///
/// Refer to the comment of each step for more information.
enum LogUpdaterStep {
  /// The build has just started.
  initial,

  /// Generic step called when the build is happening, but
  /// no specifc, or outstanding, step has been identified.
  building,

  /// The project does not have a gradle wrapper binary and it is being
  /// downloaded. (Android only)
  downloadingGradleW,

  /// Flutter is checking and preparing the Android SDK. (Android only)
  preparingAndroidSDK,

  /// The flutter assemble command is executing.
  flutterAssemble;

  /// A message that describes the step.
  ///
  /// When a step message should be defined by the user interface, this
  /// method will return null.
  String? get message {
    switch (this) {
      case LogUpdaterStep.downloadingGradleW:
        return 'Downloading Gradle Wrapper';
      case LogUpdaterStep.preparingAndroidSDK:
        return 'Preparing Android SDK';
      case LogUpdaterStep.flutterAssemble:
        return 'Assembling Flutter Resources';
      case LogUpdaterStep.initial:
      case LogUpdaterStep.building:
        return null;
    }
  }
}

/// {@template flutter_build_log_updater}
///
/// FlutterBuildLogUpdater is a class that will process the build logs
/// from a verbose flutter build command and break that down into different
/// steps in order to give a better sense of progress to the user.
///
/// {@endtemplate}
class FlutterBuildLogUpdater {
  /// {@macro flutter_build_log_updater}
  FlutterBuildLogUpdater({
    required this.onBuildStep,
  });

  final _steps = [LogUpdaterStep.initial];

  /// The steps that have been identified in the build process.
  List<LogUpdaterStep> get steps => UnmodifiableListView(_steps);

  /// The current step in the build process.
  LogUpdaterStep get currentStep => _steps.last;

  /// Callback that is called when a new step is identified in the build
  final BuildStepCallback onBuildStep;

  /// Should be called every time a new log is written to the process
  /// stdout.
  void onLog(String log) {
    if (log.contains("Running Gradle task 'bundleRelease'...") &&
        currentStep == LogUpdaterStep.initial) {
      onBuildStep(LogUpdaterStep.building);
      _steps.add(LogUpdaterStep.building);
    } else if (log.contains(
      'Downloading https://services.gradle.org/distributions/gradle',
    )) {
      onBuildStep(LogUpdaterStep.downloadingGradleW);
      _steps.add(LogUpdaterStep.downloadingGradleW);
    } else if (log.contains('Parsing') &&
        log.contains('android${platform.pathSeparator}sdk') &&
        currentStep != LogUpdaterStep.preparingAndroidSDK) {
      onBuildStep(LogUpdaterStep.preparingAndroidSDK);
      _steps.add(LogUpdaterStep.preparingAndroidSDK);
    } else if (log.contains('SDK initialized in') &&
        currentStep == LogUpdaterStep.preparingAndroidSDK) {
      onBuildStep(LogUpdaterStep.building);
      _steps.add(LogUpdaterStep.building);
    } else if (log.contains("Starting process 'command") &&
        log.contains('flutter --verbose assemble')) {
      onBuildStep(LogUpdaterStep.flutterAssemble);
      _steps.add(LogUpdaterStep.flutterAssemble);
    } else if (log.contains('exiting with code') &&
        currentStep == LogUpdaterStep.flutterAssemble) {
      onBuildStep(LogUpdaterStep.building);
      _steps.add(LogUpdaterStep.building);
    }
  }
}
