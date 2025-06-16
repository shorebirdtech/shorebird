import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(CreateCommand, () {
    const args = ['my_app'];
    late ShorebirdProcess process;
    late ArgResults argResults;
    late ShorebirdCliCommandRunner runner;
    late CreateCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {processRef.overrideWith(() => process)});
    }

    setUp(() {
      argResults = MockArgResults();
      process = MockShorebirdProcess();
      runner = MockShorebirdCliCommandRunner();
      command = runWithOverrides(CreateCommand.new)
        ..testArgResults = argResults
        ..testRunner = runner;

      when(() => argResults.rest).thenReturn(args);
      when(
        () => runner.run(any()),
      ).thenAnswer((_) async => ExitCode.success.code);
      when(
        () => process.stream('flutter', ['create', ...args]),
      ).thenAnswer((_) async => ExitCode.success.code);
    });

    test('has correct name and description', () {
      expect(command.name, equals('create'));
      expect(
        command.description,
        equals('Create a new Flutter project with Shorebird.'),
      );
    });

    test('runs the `flutter create` command', () async {
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );

      verify(() => process.stream('flutter', ['create', ...args])).called(1);
    });

    test('runs the shorebird init command', () async {
      when(() => runner.run(any())).thenAnswer((invocation) async {
        final runnerArgs = invocation.positionalArguments.first as List;
        if (runnerArgs.first == 'init') {
          expect(
            p.basename(shorebirdEnv.getFlutterProjectRoot()!.path),
            args.first,
          );
        }
        return ExitCode.success.code;
      });
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );

      verify(() => runner.run(['init'])).called(1);
    });

    group('when flutter create fails', () {
      setUp(() {
        when(
          () => process.stream('flutter', ['create', ...args]),
        ).thenAnswer((_) async => 1);
      });

      test('exits', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(equals(1)),
        );

        verify(() => process.stream('flutter', ['create', ...args])).called(1);
        verifyNever(() => runner.run(any()));
      });
    });
  });
}
