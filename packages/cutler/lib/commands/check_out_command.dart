import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cutler/config.dart';
import 'package:io/io.dart';

class CheckOutCommand extends Command<int> {
  @override
  String get name => 'checkout';

  @override
  String get description =>
      'Checks out repos required to release a new version of shorebird';

  @override
  Future<int> run() async {
    print('running checkout with root ${config.checkoutsRoot}');
    final process = await Process.start(
      'bash',
      ['bin/internal/checkout.sh', config.checkoutsRoot],
      runInShell: true,
    );

    process.stdout.transform(utf8.decoder).listen(print);
    process.stderr.transform(utf8.decoder).listen(print);

    final exitCode = await process.exitCode;

    if (exitCode != ExitCode.success.code) {
      print('checkout failed with exit code $exitCode');
      return ExitCode.software.code;
    }

    return ExitCode.success.code;
  }
}
