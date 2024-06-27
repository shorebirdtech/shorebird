import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import 'package:shorebird_cli/src/artifact_builder/flutter_build_process_tracker.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('FlutterBuildProcessTracker', () {
    late FlutterBuildProcessTracker flutterBuildProcessTracker;
    late Progress progress;

    setUp(() {
      progress = MockProgress();
      flutterBuildProcessTracker = FlutterBuildProcessTracker(
        baseMessage: 'base message',
        progress: progress,
      );
    });

    group('when reading an android build', () {
      late File androidBuildLogFile;

      setUp(() {
        androidBuildLogFile = File(
          path.join(
            'test',
            'fixtures',
            'artifact_builder',
            'android_build.txt',
          ),
        );
      });

      test(
        'correctly parses a logging output',
        () {
          final lines = androidBuildLogFile.readAsLinesSync();
          for (final line in lines) {
            flutterBuildProcessTracker.onLog(line);
          }

          final expectedSteps = [
            FlutterBuildProcessTrackerStep.initial,
            FlutterBuildProcessTrackerStep.building,
            FlutterBuildProcessTrackerStep.downloadingGradleW,
            FlutterBuildProcessTrackerStep.preparingAndroidSDK,
            FlutterBuildProcessTrackerStep.building,
            FlutterBuildProcessTrackerStep.flutterAssemble,
            FlutterBuildProcessTrackerStep.building,
          ];

          for (final step in expectedSteps) {
            expect(
              flutterBuildProcessTracker.steps,
              contains(step),
            );
          }
        },
        // The test fixtures were generated on a macOS. And some of the Build
        // Steps logic involves checking on file paths, so we run this test just
        // on unix based platforms.
        testOn: 'linux || mac-os',
      );
    });
  });
}
