import 'dart:io';

import 'package:cutler/checkout.dart';
import 'package:cutler/logger.dart';
import 'package:cutler/model.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  test('runCommand', () {
    final dartPath = Platform.executable;
    expect(
      () => runCommand(dartPath, [], workingDirectory: 'DOES_NOT_EXIST'),
      throwsA(isA<Exception>()),
    );
  });

  test('runCommand with git', () {
    final systemTemp = Directory.systemTemp;
    final temp = systemTemp.createTempSync();
    // Should this use something like:
    // https://pub.dev/packages/process_run?
    // or https://dcli.onepub.dev/dcli-api/calling-apps#which
    const gitPath = 'git';
    final result = runScoped(
      () {
        return runCommand(gitPath, ['init'], workingDirectory: temp.path);
      },
      values: {
        loggerRef.overrideWith(_MockLogger.new),
      },
    );
    expect(result, contains('Initialized empty Git repository'));
  });

  test('Checkouts', () {
    final checkouts = Checkouts('ROOT');
    expect(checkouts.dart.name, 'dart');
    expect(checkouts.engine.name, 'engine');
    expect(checkouts.flutter.name, 'flutter');
    expect(checkouts.buildroot.name, 'buildroot');
    expect(checkouts.shorebird.name, 'shorebird');
    expect(checkouts.values.length, 5);
    expect(checkouts.buildroot.workingDirectory, 'ROOT/engine/src');
    expect(checkouts.engine.workingDirectory, 'ROOT/engine/src/flutter');
    expect(checkouts.dart.workingDirectory, 'ROOT/engine/src/third_party/dart');
    expect(checkouts.flutter.workingDirectory, 'ROOT/flutter');
    expect(checkouts.shorebird.workingDirectory, 'ROOT/_shorebird/shorebird');
  });

  Directory setupCheckouts() {
    final systemTemp = Directory.systemTemp;
    final checkoutsRoot = systemTemp.createTempSync();
    for (final repo in Repo.values) {
      final dir = Directory('${checkoutsRoot.path}/${repo.path}')
        ..createSync(recursive: true);
      runCommand('git', ['init'], workingDirectory: dir.path);
      final checkout = Checkout(repo, checkoutsRoot.path)
        ..writeFile('NAME', repo.name);
      runCommand('git', ['add', 'NAME'], workingDirectory: dir.path);
      // Git requires user.email user.name to be set before committing.
      runCommand(
        'git',
        ['config', 'user.email', 'test@shorebird.dev'],
        workingDirectory: dir.path,
      );
      runCommand(
        'git',
        ['config', 'user.name', 'Cutler Checkout Test'],
        workingDirectory: dir.path,
      );
      checkout.commit('Test commit');
    }
    return checkoutsRoot;
  }

  test('Checkouts real git commands', () {
    runScoped(
      () {
        final root = setupCheckouts();
        final checkouts = Checkouts(root.path);
        expect(checkouts.dart.contentsAtPath('HEAD', 'NAME'), 'dart');
        expect(checkouts.engine.contentsAtPath('HEAD', 'NAME'), 'engine');
        expect(checkouts.flutter.contentsAtPath('HEAD', 'NAME'), 'flutter');
        expect(checkouts.buildroot.contentsAtPath('HEAD', 'NAME'), 'buildroot');
        expect(checkouts.shorebird.contentsAtPath('HEAD', 'NAME'), 'shorebird');
      },
      values: {
        loggerRef.overrideWith(_MockLogger.new),
      },
    );
  });
}
