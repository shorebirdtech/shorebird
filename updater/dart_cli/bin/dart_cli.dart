import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_bindings/updater.dart';
import 'package:path/path.dart' as path;

void main(List<String> args) async {
  var directory = path.join(Directory.current.path, 'target', 'debug');
  Updater.loadLibrary(directory: directory, name: "updater");

  Updater.initUpdaterLibrary(
    clientId: 'my-client-id',
    appId: 'demo',
    version: '1.0.0',
    channel: 'stable',
    updateUrl: null,
    baseLibraryPath: 'libapp.so',
    vmPath: Platform.executable,
    cacheDir: 'updater_cache',
  );

  var updater = Updater();
  final runner = CommandRunner<void>('updater', 'Updater CLI')
    ..addCommand(CheckForUpdate(updater))
    ..addCommand(PrintVersion(updater))
    ..addCommand(PrintPath(updater))
    ..addCommand(Update(updater))
    ..addCommand(Run(updater));
  await runner.run(args);
}

class CheckForUpdate extends Command<void> {
  final Updater updater;
  CheckForUpdate(this.updater);

  @override
  final name = 'check';

  @override
  final description = 'Check for an update.';

  @override
  void run() {
    var result = updater.checkForUpdate();
    if (result) {
      print('Update available');
    } else {
      print('No update available');
    }
  }
}

class PrintVersion extends Command<void> {
  final Updater updater;
  PrintVersion(this.updater);

  @override
  final name = 'version';

  @override
  final description = 'Print current installed version.';

  @override
  void run() {
    print(updater.activeVersion());
  }
}

class PrintPath extends Command<void> {
  final Updater updater;
  PrintPath(this.updater);

  @override
  final name = 'path';

  @override
  final description = 'Print current installed path.';

  @override
  void run() {
    print(updater.activePath());
  }
}

class Update extends Command<void> {
  final Updater updater;
  Update(this.updater);

  @override
  final name = 'update';

  @override
  final description = 'Update to the latest version.';

  @override
  void run() {
    updater.update();
  }
}

class Run extends Command<void> {
  final Updater updater;
  Run(this.updater) {
    argParser.addFlag('update', abbr: 'u', help: 'Update before running.');
  }

  @override
  final name = 'run';

  @override
  final description = 'Run the active version.';

  @override
  void run() async {
    // This is a basic demo of what this might look like.
    // Real callers wouldn't likely do this from Dart as there is no need
    // to have two copies of the Dart VM running.

    if (argResults!['update']) {
      updater.update();
    }

    var path = updater.activePath();
    if (path == null) {
      print('No active version (should run the bundled version)');
      return;
    }
    // Should this run update first?
    print('Running $path');
    // Is there a portable way to just "exec" and replace the current process?
    var process = await Process.start(Platform.executable, ['run', path]);
    process.stdout.transform(utf8.decoder).forEach(stdout.write);
    process.stderr.transform(utf8.decoder).forEach(stderr.write);
    // TODO: Handle stdin.
    exit(await process.exitCode);
  }
}
