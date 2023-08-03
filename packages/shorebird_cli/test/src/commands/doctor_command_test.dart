import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockDoctor extends Mock implements Doctor {}

class _MockLogger extends Mock implements Logger {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockValidator extends Mock implements Validator {}

void main() {
  group('doctor', () {
    const shorebirdEngineRevision = 'test-revision';

    late ArgResults argResults;
    late Doctor doctor;
    late DoctorCommand command;
    late Logger logger;
    late ShorebirdEnv shorebirdEnv;
    late Validator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      doctor = _MockDoctor();
      logger = _MockLogger();
      shorebirdEnv = _MockShorebirdEnv();
      validator = _MockValidator();

      when(
        () => shorebirdEnv.shorebirdEngineRevision(
          flutterRevision: any(named: 'flutterRevision'),
        ),
      ).thenReturn(shorebirdEngineRevision);
      when(() => doctor.allValidators).thenReturn([validator]);
      when(
        () => doctor.runValidators(any(), applyFixes: any(named: 'applyFixes')),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(DoctorCommand.new)
        ..testArgResults = argResults;
    });

    test('prints shorebird version and engine revision', () async {
      await runWithOverrides(command.run);

      verify(
        () => logger.info('''

Shorebird v$packageVersion
Shorebird Engine • revision $shorebirdEngineRevision
'''),
      ).called(1);
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
