import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/flutter/config/flutter_config_command.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../../../mocks.dart';

void main() {
  group(FlutterConfigCommand, () {
    late ShorebirdProcess process;
    late ArgResults argResults;
    late FlutterConfigCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {processRef.overrideWith(() => process)});
    }

    setUp(() {
      argResults = MockArgResults();
      process = MockShorebirdProcess();
      command = runWithOverrides(FlutterConfigCommand.new)
        ..testArgResults = argResults;
    });

    test('has correct name and description', () {
      expect(command.name, equals('config'));
      expect(
        command.description,
        equals(
          'Configure Flutter settings. This proxies to the underlying `flutter config` command.',
        ),
      );
    });

    test('runs the `flutter config` command', () async {
      final exitCode = ExitCode.success.code;
      final args = ['--jdk-dir', '/path/to/jdk'];
      when(() => argResults.rest).thenReturn(args);
      when(
        () => process.stream('flutter', ['config', ...args]),
      ).thenAnswer((_) async => exitCode);

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exitCode)),
      );

      verify(() => process.stream('flutter', ['config', ...args])).called(1);
    });
  });
}
