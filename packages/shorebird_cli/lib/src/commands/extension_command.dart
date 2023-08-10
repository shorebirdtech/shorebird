import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shorebird_cli/src/logger.dart';

class ExtensionCommand extends Command<int> {
  ExtensionCommand(this.commandName, this.executableName, this.commandUsage);

  final String commandName;
  final String executableName;
  final String commandUsage;

  @override
  String get description => 'a Shorebird extension command';

  @override
  String get name => commandName;

  @override
  String get usage {
    return commandUsage;
  }

  @override
  FutureOr<int> run() async {
    final arguments = argResults?.arguments ?? List<String>.empty();
    final process = await Process.start(executableName, arguments);
    Future<void> outStream(p) async {
      await process.stdout.transform(utf8.decoder).forEach(logger.info);
    }

    Future<void> errStream(p) async {
      await process.stderr.transform(utf8.decoder).forEach(logger.info);
    }

    await Future.wait([outStream(process), errStream(process)]);
    return process.exitCode;
  }
}

(bool, String) checkForExecutableExtension(String executableName) {
  var extensionExists = false;
  var extensionUsage = '';

  try {
    final processResult = Process.runSync(executableName, List.empty());
    extensionExists = true;
    extensionUsage = processResult.stdout.toString();
  } catch (e) {
    return (false, '');
  }

  return (extensionExists, extensionUsage);
}

extension ExtensionsLoader on CommandRunner<int> {
  void preprocess(Iterable<String> args) {
    for (final arg in args) {
      if (arg.startsWith(RegExp('[-]+'))) {
        continue;
      }

      final possibleExtension = !commands.containsKey(arg);
      if (possibleExtension) {
        final commandName = arg;
        final executableName = 'shorebird-$commandName';
        final (extensionExists, extensionUsage) =
            checkForExecutableExtension(executableName);
        if (extensionExists) {
          addCommand(
              ExtensionCommand(commandName, executableName, extensionUsage),);
        }
      }
      break;
    }
  }
}
