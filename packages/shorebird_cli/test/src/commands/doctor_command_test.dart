import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAndroidStudio extends Mock implements AndroidStudio {}

class _MockAndroidSdk extends Mock implements AndroidSdk {}

class _MockDoctor extends Mock implements Doctor {}

class _MockJava extends Mock implements Java {}

class _MockLogger extends Mock implements Logger {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdFlutter extends Mock implements ShorebirdFlutter {}

class _MockValidator extends Mock implements Validator {}

void main() {
  group('doctor', () {
    const shorebirdEngineRevision = 'test-engine-revision';
    const shorebirdFlutterRevision = 'test-flutter-revision';

    late ArgResults argResults;
    late AndroidStudio androidStudio;
    late AndroidSdk androidSdk;
    late Doctor doctor;
    late Java java;
    late Logger logger;
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
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      androidStudio = _MockAndroidStudio();
      androidSdk = _MockAndroidSdk();
      doctor = _MockDoctor();
      java = _MockJava();
      logger = _MockLogger();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdFlutter = _MockShorebirdFlutter();
      validator = _MockValidator();

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
        () => shorebirdFlutter.getVersion(),
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
        verify(
          () => logger.info('''

Shorebird v$packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter • revision ${shorebirdEnv.flutterRevision}
Engine • revision $shorebirdEngineRevision

Android Toolchain
  • Android Studio: $notDetectedText
  • Android SDK: $notDetectedText
  • ADB: $notDetectedText
  • JAVA_HOME: $notDetectedText'''),
        ).called(1);
      });

      test('prints additional information (detected)', () async {
        when(() => argResults['verbose']).thenReturn(true);
        when(() => androidStudio.path).thenReturn('test-studio-path');
        when(() => androidSdk.path).thenReturn('test-sdk-path');
        when(() => androidSdk.adbPath).thenReturn('test-adb-path');
        when(() => java.home).thenReturn('test-java-home');
        await runWithOverrides(command.run);

        verify(
          () => logger.info('''

Shorebird v$packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter • revision ${shorebirdEnv.flutterRevision}
Engine • revision $shorebirdEngineRevision

Android Toolchain
  • Android Studio: test-studio-path
  • Android SDK: test-sdk-path
  • ADB: test-adb-path
  • JAVA_HOME: test-java-home'''),
        ).called(1);
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
