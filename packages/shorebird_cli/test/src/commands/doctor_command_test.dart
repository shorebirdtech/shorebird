import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/network_checker.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('doctor', () {
    const shorebirdEngineRevision = 'test-engine-revision';
    const shorebirdFlutterRevision = 'test-flutter-revision';

    late ArgResults argResults;
    late AndroidStudio androidStudio;
    late AndroidSdk androidSdk;
    late Directory logsDirectory;
    late Doctor doctor;
    late Gradlew gradlew;
    late Java java;
    late NetworkChecker networkChecker;
    late Progress progress;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late Validator validator;
    late DoctorCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          androidStudioRef.overrideWith(() => androidStudio),
          androidSdkRef.overrideWith(() => androidSdk),
          doctorRef.overrideWith(() => doctor),
          gradlewRef.overrideWith(() => gradlew),
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          networkCheckerRef.overrideWith(() => networkChecker),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      androidStudio = MockAndroidStudio();
      androidSdk = MockAndroidSdk();
      doctor = MockDoctor();
      gradlew = MockGradlew();
      logsDirectory = Directory.systemTemp.createTempSync('shorebird_logs');
      java = MockJava();
      logger = MockShorebirdLogger();
      networkChecker = MockNetworkChecker();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      validator = MockValidator();

      when(() => argResults['verbose']).thenReturn(false);
      when(() => argResults['fix']).thenReturn(false);
      when(() => androidStudio.path).thenReturn(null);
      when(() => androidSdk.path).thenReturn(null);
      when(() => androidSdk.adbPath).thenReturn(null);
      when(() => gradlew.exists(any())).thenReturn(false);
      when(() => java.home).thenReturn(null);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => networkChecker.checkReachability(),
      ).thenAnswer((_) async => {});
      when(
        () => networkChecker.performGCPDownloadSpeedTest(),
      ).thenAnswer((_) async => 1.0);
      when(
        () => networkChecker.performGCPUploadSpeedTest(),
      ).thenAnswer((_) async => 1.0);
      when(
        () => shorebirdEnv.shorebirdEngineRevision,
      ).thenReturn(shorebirdEngineRevision);
      when(
        () => shorebirdEnv.flutterRevision,
      ).thenReturn(shorebirdFlutterRevision);
      when(() => shorebirdEnv.logsDirectory).thenReturn(logsDirectory);
      when(() => doctor.generalValidators).thenReturn([validator]);
      when(
        () => doctor.runValidators(any(), applyFixes: any(named: 'applyFixes')),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(DoctorCommand.new)
        ..testArgResults = argResults;
    });

    test(
        'prints shorebird version, flutter revision, '
        'and engine revision', () async {
      await runWithOverrides(command.run);

      verify(
        () => logger.info('''

Shorebird v$packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter • revision ${shorebirdEnv.flutterRevision}
Engine • revision $shorebirdEngineRevision
'''),
      ).called(1);
    });

    test(
        '''prints shorebird version, flutter revision, flutter version, and engine revision''',
        () async {
      const flutterVersion = '1.2.3';
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => flutterVersion);
      await runWithOverrides(command.run);

      verify(
        () => logger.info('''

Shorebird v$packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter $flutterVersion • revision ${shorebirdEnv.flutterRevision}
Engine • revision $shorebirdEngineRevision
'''),
      ).called(1);
      verify(() => networkChecker.checkReachability()).called(1);
      verifyNever(() => networkChecker.performGCPDownloadSpeedTest());
      verifyNever(() => networkChecker.performGCPUploadSpeedTest());
    });

    group('--verbose', () {
      setUp(() {
        when(() => argResults['verbose']).thenReturn(true);
        when(
          () => networkChecker.performGCPDownloadSpeedTest(),
        ).thenAnswer((_) async => 1.987654321);
        when(
          () => networkChecker.performGCPUploadSpeedTest(),
        ).thenAnswer((_) async => 1.23456789);
      });

      test('prints additional information (not detected)', () async {
        await runWithOverrides(command.run);

        final notDetectedText = red.wrap('not detected');
        final msg =
            verify(() => logger.info(captureAny())).captured.first as String;

        expect(
          msg,
          equals('''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter • revision ${shorebirdEnv.flutterRevision}
Engine • revision $shorebirdEngineRevision

Logs: ${logsDirectory.path}
Android Toolchain
  • Android Studio: $notDetectedText
  • Android SDK: $notDetectedText
  • ADB: $notDetectedText
  • JAVA_HOME: $notDetectedText
  • JAVA_EXECUTABLE: $notDetectedText
  • JAVA_VERSION: $notDetectedText
  • Gradle: $notDetectedText
'''),
        );
      });

      test('prints additional information (detected)', () async {
        when(() => androidStudio.path).thenReturn('test-studio-path');
        when(() => androidSdk.path).thenReturn('test-sdk-path');
        when(() => androidSdk.adbPath).thenReturn('test-adb-path');
        when(() => java.home).thenReturn('test-java-home');
        when(() => java.executable).thenReturn('test-java-executable');

        when(() => java.version).thenReturn(
          '''
openjdk version "17.0.9" 2023-10-17
OpenJDK Runtime Environment (build 17.0.9+0-17.0.9b1087.7-11185874)
OpenJDK 64-Bit Server VM (build 17.0.9+0-17.0.9b1087.7-11185874, mixed mode)'''
              .replaceAll('\n', Platform.lineTerminator),
        );
        await runWithOverrides(command.run);

        final msg =
            verify(() => logger.info(captureAny())).captured.first as String;

        final notDetectedText = red.wrap('not detected');
        expect(
          msg.replaceAll(
            Platform.lineTerminator,
            '\n',
          ),
          equals(
            '''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter • revision ${shorebirdEnv.flutterRevision}
Engine • revision $shorebirdEngineRevision

Logs: ${logsDirectory.path}
Android Toolchain
  • Android Studio: test-studio-path
  • Android SDK: test-sdk-path
  • ADB: test-adb-path
  • JAVA_HOME: test-java-home
  • JAVA_EXECUTABLE: test-java-executable
  • JAVA_VERSION: openjdk version "17.0.9" 2023-10-17
                  OpenJDK Runtime Environment (build 17.0.9+0-17.0.9b1087.7-11185874)
                  OpenJDK 64-Bit Server VM (build 17.0.9+0-17.0.9b1087.7-11185874, mixed mode)
  • Gradle: $notDetectedText
''',
          ),
        );

        verify(() => networkChecker.checkReachability()).called(1);
        verify(() => networkChecker.performGCPDownloadSpeedTest()).called(1);
        verify(
          () => progress.complete('GCP Download Speed: 1.99 MB/s'),
        ).called(1);
        verify(() => networkChecker.performGCPUploadSpeedTest()).called(1);
        verify(
          () => progress.complete('GCP Upload Speed: 1.23 MB/s'),
        ).called(1);
      });

      group('when a gradlew executable exists', () {
        setUp(() {
          when(() => gradlew.exists(any())).thenReturn(true);
          when(() => gradlew.version(any())).thenAnswer((_) async => '7.6.3');
          when(() => androidStudio.path).thenReturn('test-studio-path');
          when(() => androidSdk.path).thenReturn('test-sdk-path');
          when(() => androidSdk.adbPath).thenReturn('test-adb-path');
          when(() => java.home).thenReturn('test-java-home');
          when(() => java.executable).thenReturn('test-java-executable');

          when(() => java.version).thenReturn(
            '''
openjdk version "17.0.9" 2023-10-17
OpenJDK Runtime Environment (build 17.0.9+0-17.0.9b1087.7-11185874)
OpenJDK 64-Bit Server VM (build 17.0.9+0-17.0.9b1087.7-11185874, mixed mode)'''
                .replaceAll('\n', Platform.lineTerminator),
          );
        });

        test('prints the gradle version', () async {
          await runWithOverrides(command.run);

          final msg =
              verify(() => logger.info(captureAny())).captured.first as String;

          expect(
            msg.replaceAll(
              Platform.lineTerminator,
              '\n',
            ),
            equals(
              '''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter • revision ${shorebirdEnv.flutterRevision}
Engine • revision $shorebirdEngineRevision

Logs: ${logsDirectory.path}
Android Toolchain
  • Android Studio: test-studio-path
  • Android SDK: test-sdk-path
  • ADB: test-adb-path
  • JAVA_HOME: test-java-home
  • JAVA_EXECUTABLE: test-java-executable
  • JAVA_VERSION: openjdk version "17.0.9" 2023-10-17
                  OpenJDK Runtime Environment (build 17.0.9+0-17.0.9b1087.7-11185874)
                  OpenJDK 64-Bit Server VM (build 17.0.9+0-17.0.9b1087.7-11185874, mixed mode)
  • Gradle: 7.6.3
''',
            ),
          );
        });
      });

      group('when gcp upload speed test fails', () {
        setUp(() {
          const flutterVersion = '1.2.3';
          when(
            () => shorebirdFlutter.getVersionString(),
          ).thenAnswer((_) async => flutterVersion);
        });

        group('with NetworkCheckerException', () {
          setUp(() {
            when(
              () => networkChecker.performGCPUploadSpeedTest(),
            ).thenThrow(const NetworkCheckerException('oops'));
          });

          test('logs error as detail, continues', () async {
            await expectLater(
              runWithOverrides(command.run),
              completes,
            );

            verify(
              () => progress.fail('GCP upload speed test failed: oops'),
            ).called(1);
          });
        });

        group('with generic Exception', () {
          setUp(() {
            when(
              () => networkChecker.performGCPUploadSpeedTest(),
            ).thenThrow(Exception('oops'));
          });

          test('logs error as detail, continues', () async {
            await expectLater(
              runWithOverrides(command.run),
              completes,
            );

            verify(
              () => progress.fail(
                'GCP upload speed test failed: Exception: oops',
              ),
            ).called(1);
          });
        });
      });

      group('when gcp download speed test fails', () {
        setUp(() {
          const flutterVersion = '1.2.3';
          when(
            () => shorebirdFlutter.getVersionString(),
          ).thenAnswer((_) async => flutterVersion);
        });

        group('with NetworkCheckerException', () {
          setUp(() {
            when(
              () => networkChecker.performGCPDownloadSpeedTest(),
            ).thenThrow(const NetworkCheckerException('oops'));
          });

          test('logs error as detail, continues', () async {
            await expectLater(
              runWithOverrides(command.run),
              completes,
            );

            verify(
              () => progress.fail('GCP download speed test failed: oops'),
            ).called(1);
          });
        });

        group('with generic Exception', () {
          setUp(() {
            when(
              () => networkChecker.performGCPDownloadSpeedTest(),
            ).thenThrow(Exception('oops'));
          });

          test('logs error as detail, continues', () async {
            await expectLater(
              runWithOverrides(command.run),
              completes,
            );

            verify(
              () => progress.fail(
                'GCP download speed test failed: Exception: oops',
              ),
            ).called(1);
          });
        });
      });
    });

    test('runs validators without applying fixes if no fix flag exists',
        () async {
      when(() => argResults['fix']).thenReturn(null);
      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(() => doctor.runValidators([validator])).called(1);
    });

    test('runs validators and applies fixes fix flag is true', () async {
      when(() => argResults['fix']).thenReturn(true);
      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => doctor.runValidators([validator], applyFixes: true),
      ).called(1);
    });
  });
}
