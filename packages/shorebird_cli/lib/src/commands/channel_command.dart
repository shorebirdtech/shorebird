import 'dart:io';
import 'package:args/command_runner.dart';

class ChannelCommand extends Command {
  @override
  final String name = 'channel';

  @override
  final String description = 'Switch to a different Shorebird channel.';

  @override
  void run() async {
    final branch = argResults.rest.isNotEmpty ? argResults.rest[0] : null;
    if (branch == null) {
      print('Please provide a branch name to switch to.');
      return;
    }

    final result = await Process.run('git', ['checkout', branch]);
    if (result.exitCode == 0) {
      print('Switched to branch $branch');
    } else {
      print('Error switching to branch $branch: ${result.stderr}');
    }
  }
}
