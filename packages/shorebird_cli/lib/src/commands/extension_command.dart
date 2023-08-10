import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';

class ExtensionCommand extends ShorebirdCommand {
  ExtensionCommand(this.extensionName);

  final String extensionName;

  @override
  String get description => 'A Shorebird extension command for $extensionName';

  @override
  String get name => extensionName;

  static String executableName(String extensionName) {
    return 'shorebird-$extensionName';
  }

  static Future<bool> canExecute(String extensionName) async {
    try {
      final executableName = ExtensionCommand.executableName(extensionName);
      final processResult = await process.run(executableName, List.empty());
      return processResult.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  @override
  FutureOr<int> run() async {
    final arguments = results.arguments;
    final executableName = ExtensionCommand.executableName(extensionName);
    final runningProcess = await process.start(executableName, arguments);

    Future<void> outStream(p) async {
      await runningProcess.stdout.transform(utf8.decoder).forEach(logger.info);
    }

    Future<void> errStream(p) async {
      await runningProcess.stderr.transform(utf8.decoder).forEach(logger.err);
    }

    await Future.wait([outStream(process), errStream(process)]);
    return runningProcess.exitCode;
  }
}

extension ShorebirdExtensionsCommandRunner on CommandRunner<int> {
  Future<void> preprocess(Iterable<String> args) async {
    for (final arg in args) {
      if (arg.startsWith(RegExp('[-]+'))) {
        continue;
      }

      final possibleExtension = !commands.containsKey(arg);
      if (possibleExtension) {
        final commandName = arg;
        final canExecuteExtension =
            await ExtensionCommand.canExecute(commandName);
        if (canExecuteExtension) {
          addCommand(ExtensionCommand(commandName));
        }
      }
      break;
    }
  }
}
