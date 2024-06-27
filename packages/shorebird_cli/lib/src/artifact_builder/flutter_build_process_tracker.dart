import 'dart:collection';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// This enum describes the different steps that the log updater
/// identifies in the build process.
///
/// Not all of the steps apply to all platforms or to the situation of the
/// user's build (e.g. [downloadingGradleW] only applies to Android projects
/// in the first build).
///
/// Refer to the comment of each step for more information.
enum FlutterBuildProcessTrackerStep {
  /// The build has just started.
  initial,

  /// Generic step called when the build is happening, but
  /// no specifc, or outstanding, step has been identified.
  building,

  /// The project does not have a gradle wrapper binary and it is being
  /// downloaded. (Android only)
  downloadingGradleW,

  /// The project is downloading a Gradle dependency. (Android only)
  downloadingGradleDependency,

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
      case FlutterBuildProcessTrackerStep.downloadingGradleW:
        return 'Downloading Gradle Wrapper';
      case FlutterBuildProcessTrackerStep.downloadingGradleDependency:
        return 'Downloading Gradle Dependency';
      case FlutterBuildProcessTrackerStep.preparingAndroidSDK:
        return 'Preparing Android SDK';
      case FlutterBuildProcessTrackerStep.flutterAssemble:
        return 'Assembling Flutter Resources';
      case FlutterBuildProcessTrackerStep.initial:
      case FlutterBuildProcessTrackerStep.building:
        return null;
    }
  }
}

/// {@template flutter_build_log_updater}
///
/// FlutterBuildProcessTracker is a class that will process the build logs
/// from a verbose flutter build command and break that down into different
/// steps in order to give a better sense of progress to the user.
///
/// {@endtemplate}
class FlutterBuildProcessTracker extends ShorebirdProcessTracker {
  /// {@macro flutter_build_log_updater}
  FlutterBuildProcessTracker({
    required this.baseMessage,
    Progress? progress,
  }) : progress = progress ?? logger.progress(baseMessage);

  /// The overlaying message of the build process.
  final String baseMessage;

  /// The progress object that will update the user interface.
  late final Progress progress;

  final _steps = [FlutterBuildProcessTrackerStep.initial];

  /// The steps that have been identified in the build process.
  List<FlutterBuildProcessTrackerStep> get steps =>
      UnmodifiableListView(_steps);

  /// The current step in the build process.
  FlutterBuildProcessTrackerStep get currentStep => _steps.last;

  @override
  void onLog(String logLine) {
    super.onLog(logLine);
    if (logLine.contains("Running Gradle task 'bundleRelease'...") &&
        currentStep == FlutterBuildProcessTrackerStep.initial) {
      _emitStep(FlutterBuildProcessTrackerStep.building);
    } else if (logLine.contains(
      'Downloading https://services.gradle.org/distributions/gradle',
    )) {
      _emitStep(FlutterBuildProcessTrackerStep.downloadingGradleW);
    } else if (logLine.contains('Downloading') && logLine.contains('.gradle')) {
      _emitStep(FlutterBuildProcessTrackerStep.downloadingGradleDependency);
    } else if (logLine.contains('Parsing') &&
        logLine.contains('android${platform.pathSeparator}sdk') &&
        currentStep != FlutterBuildProcessTrackerStep.preparingAndroidSDK) {
      _emitStep(FlutterBuildProcessTrackerStep.preparingAndroidSDK);
    } else if (logLine.contains('SDK initialized in') &&
        currentStep == FlutterBuildProcessTrackerStep.preparingAndroidSDK) {
      _emitStep(FlutterBuildProcessTrackerStep.building);
    } else if (logLine.contains("Starting process 'command") &&
        logLine.contains('flutter --verbose assemble')) {
      _emitStep(FlutterBuildProcessTrackerStep.flutterAssemble);
    } else if (logLine.contains('exiting with code') &&
        currentStep == FlutterBuildProcessTrackerStep.flutterAssemble) {
      _emitStep(FlutterBuildProcessTrackerStep.building);
      // If he last step was a downloading gradle and nothing else matched
      // then we know that the download is over.
    } else if (currentStep ==
        FlutterBuildProcessTrackerStep.downloadingGradleDependency) {
      final lastNonGradleDownload = _steps.lastWhere(
        (step) =>
            step !=
                FlutterBuildProcessTrackerStep.downloadingGradleDependency &&
            step != FlutterBuildProcessTrackerStep.downloadingGradleW,
        orElse: () => FlutterBuildProcessTrackerStep.building,
      );
      _emitStep(lastNonGradleDownload);
    }
  }

  void _emitStep(FlutterBuildProcessTrackerStep step) {
    if (step == currentStep) return;
    progress.update(step.message ?? baseMessage);
    _steps.add(step);
  }
}
