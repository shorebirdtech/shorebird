import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shorebird_cli/src/artifact_builder/flutter_build_log_updater.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterBuildLogUpdater', () {
    late FlutterBuildLogUpdater flutterBuildLogUpdater;

    setUp(() {
      flutterBuildLogUpdater = FlutterBuildLogUpdater(
        onBuildStep: (_) {},
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
            flutterBuildLogUpdater.onLog(line);
          }

          expect(
            flutterBuildLogUpdater.steps,
            equals([
              LogUpdaterStep.initial,
              LogUpdaterStep.building,
              LogUpdaterStep.downloadingGradleW,
              LogUpdaterStep.preparingAndroidSDK,
              LogUpdaterStep.building,
              LogUpdaterStep.flutterAssemble,
              LogUpdaterStep.building,
            ]),
          );
        },
        // The test fixtures were generated on a macOS. And some of the Build
        // Steps logic involves checking on file paths, so we run this test just
        // on unix based platforms.
        testOn: 'linux || mac-os',
      );
    });
  });
}
