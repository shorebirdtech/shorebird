import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
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
    late Java java;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;
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
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          processRef.overrideWith(() => shorebirdProcess),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      androidStudio = MockAndroidStudio();
      androidSdk = MockAndroidSdk();
      doctor = MockDoctor();
      logsDirectory = Directory.systemTemp.createTempSync('shorebird_logs');
      java = MockJava();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdProcess = MockShorebirdProcess();
      validator = MockValidator();

      when(() => argResults['verbose']).thenReturn(false);
      when(() => argResults['fix']).thenReturn(false);
      when(() => androidStudio.path).thenReturn(null);
      when(() => androidSdk.path).thenReturn(null);
      when(() => androidSdk.adbPath).thenReturn(null);
      when(() => java.home).thenReturn(null);
      when(
        () => shorebirdEnv.shorebirdEngineRevision,
      ).thenReturn(shorebirdEngineRevision);
      when(
        () => shorebirdEnv.flutterRevision,
      ).thenReturn(shorebirdFlutterRevision);
      when(() => shorebirdEnv.logsDirectory).thenReturn(logsDirectory);
      when(() => doctor.allValidators).thenReturn([validator]);
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
        'prints shorebird version, flutter revision, '
        'flutter version, and engine revision', () async {
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
    });

    group('--verbose', () {
      test('prints additional information (not detected)', () async {
        when(() => argResults['verbose']).thenReturn(true);
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
'''),
        );
      });

      test('prints additional information (detected)', () async {
        when(() => argResults['verbose']).thenReturn(true);
        when(() => androidStudio.path).thenReturn('test-studio-path');
        when(() => androidSdk.path).thenReturn('test-sdk-path');
        when(() => androidSdk.adbPath).thenReturn('test-adb-path');
        when(() => java.home).thenReturn('test-java-home');
        when(() => java.executable).thenReturn('test-java-executable');

        final result = MockShorebirdProcessResult();
        when(() => result.exitCode).thenReturn(ExitCode.success.code);
        when(() => result.stderr).thenReturn('''
openjdk version "17.0.9" 2023-10-17
OpenJDK Runtime Environment (build 17.0.9+0-17.0.9b1087.7-11185874)
OpenJDK 64-Bit Server VM (build 17.0.9+0-17.0.9b1087.7-11185874, mixed mode)''');
        when(
          () => shorebirdProcess.runSync(
            'test-java-executable',
            ['-version'],
          ),
        ).thenReturn(result);
        await runWithOverrides(command.run);

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
  • Android Studio: test-studio-path
  • Android SDK: test-sdk-path
  • ADB: test-adb-path
  • JAVA_HOME: test-java-home
  • JAVA_EXECUTABLE: test-java-executable
  • JAVA_VERSION: openjdk version "17.0.9" 2023-10-17
                  OpenJDK Runtime Environment (build 17.0.9+0-17.0.9b1087.7-11185874)
                  OpenJDK 64-Bit Server VM (build 17.0.9+0-17.0.9b1087.7-11185874, mixed mode)
'''),
        );
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
