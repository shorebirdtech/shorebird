import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/commands/extension_command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';

import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcess extends Mock implements Process {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdProcessResult extends Mock
    implements ShorebirdProcessResult {}

class _MockIOSink extends Mock implements IOSink {}

void main() {
  late ArgResults argResults;
  late Logger logger;
  late Process process;
  late ShorebirdProcess shorebirdProcess;
  late ShorebirdProcessResult shorebirdProcessResult;
  late IOSink ioSink;
  late ShorebirdCliCommandRunner commandRunner;
  late ExtensionCommand command;
  late String commandOutput;

  Map<String, Command<int>> getExtensionCommands() {
    final extensionCommands = <String, ExtensionCommand>{};
    commandRunner.commands.forEach((key, value) {
      if (value is ExtensionCommand) {
        extensionCommands[key] = value;
      }
    });
    return extensionCommands;
  }

  bool hasExtensionCommands() {
    return getExtensionCommands().isNotEmpty;
  }

  R runWithOverrides<R>(R Function() body) {
    return runScoped(
      body,
      values: {
        loggerRef.overrideWith(() => logger),
        processRef.overrideWith(() => shorebirdProcess)
      },
    );
  }

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  setUp(() {
    argResults = _MockArgResults();
    logger = _MockLogger();
    process = _MockProcess();
    shorebirdProcess = _MockShorebirdProcess();
    shorebirdProcessResult = _MockShorebirdProcessResult();

    commandOutput =
        File(p.join('test', 'fixtures', 'extensions', 'shorebird-extension'))
            .readAsStringSync();
    ioSink = _MockIOSink();

    when(
      () => shorebirdProcess.start(
        any(),
        any(),
        runInShell: any(named: 'runInShell'),
      ),
    ).thenAnswer((_) async => process);

    when(
      () => shorebirdProcess.run(
        any(),
        any(),
        runInShell: any(named: 'runInShell'),
      ),
    ).thenAnswer((_) async => shorebirdProcessResult);

    when(() => argResults.arguments).thenReturn(List<String>.empty());
    when(() => argResults.rest).thenReturn([]);
    when(() => logger.progress(any())).thenReturn(_MockProgress());
    when(() => ioSink.addStream(any())).thenAnswer((_) async {});

    commandRunner = runWithOverrides(ShorebirdCliCommandRunner.new);
    command = runWithOverrides(() => ExtensionCommand('extension'))
      ..testArgResults = argResults;
  });

  test('has a description', () {
    expect(command.description, isNotEmpty);
  });

  group('validate extensions to CommandRunner', () {
    test(
        'command runner with no options or arguments will not have any '
        'extension commands', () async {
      final args = List<String>.empty();
      await runWithOverrides(() => commandRunner.preprocess(args));
      expect(hasExtensionCommands(), false);
    });

    test('command runner with all options will not have any extension commands',
        () async {
      const args = ['--option1', '--option2', '--option3'];
      await runWithOverrides(() => commandRunner.preprocess(args));
      expect(hasExtensionCommands(), false);
    });

    test(
        'command runner with options and a known command will not have an '
        'extension command', () async {
      const args = ['--option1', '--option2', '--option3', 'doctor'];
      await runWithOverrides(() => commandRunner.preprocess(args));

      expect(hasExtensionCommands(), false);
    });

    test(
        'command runner with a known command and options will not have an '
        'extension command', () async {
      const args = ['doctor', '--option1', '---option2', '--option3'];
      await runWithOverrides(() => commandRunner.preprocess(args));
      expect(hasExtensionCommands(), false);
    });

    test(
        'command runner with an unknown command that is executable will have an'
        ' extension command', () async {
      const commandName = 'myunknowncommand';
      const args = [commandName];
      when(
        () => shorebirdProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);

      await runWithOverrides(() => commandRunner.preprocess(args));

      final extensionCommands = getExtensionCommands();

      expect(extensionCommands.length, 1);
      expect(extensionCommands.containsKey(commandName), true);
    });

    test(
        'command runner with an unknown command that is not executable will '
        'not have an extension command', () async {
      const commandName = 'myunknowncommand';
      const args = [commandName];
      when(
        () => shorebirdProcessResult.exitCode,
      ).thenReturn(ExitCode.software.code);

      await runWithOverrides(() => commandRunner.preprocess(args));

      final extensionCommands = getExtensionCommands();

      expect(extensionCommands.length, 0);
      expect(extensionCommands.containsKey(commandName), false);
    });

    test(
        'command runner with an unknown command that throws an exception '
        'on execution will not have an extension command', () async {
      const commandName = 'myunknowncommand';
      const args = [commandName];
      when(() => shorebirdProcess.run(any(), any())).thenThrow(Exception());

      await runWithOverrides(() => commandRunner.preprocess(args));

      final extensionCommands = getExtensionCommands();

      expect(extensionCommands.length, 0);
      expect(extensionCommands.containsKey(commandName), false);
    });
  });

  group('validate an extension command can be executed', () {
    test(
        'command runner with an known command that is executable completes'
        ' succesfully', () async {
      when(
        () => shorebirdProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);

      when(
        () => process.stdout,
      ).thenAnswer((_) => Stream.value(utf8.encode(commandOutput)));
      when(() => process.stdin).thenAnswer((_) => ioSink);
      when(() => process.stderr).thenAnswer((_) => const Stream.empty());
      when(() => process.exitCode).thenAnswer((_) async => exitCode);

      when(
        () => shorebirdProcess.start(
          any(),
          any(),
        ),
      ).thenAnswer((_) async => process);

      await runWithOverrides(() => command.run());

      verify(
        () => shorebirdProcess.start(
          'shorebird-extension',
          [],
        ),
      ).called(1);

      verify(
        () => logger.info(any(that: contains(commandOutput))),
      ).called(1);
    });
  });
}
