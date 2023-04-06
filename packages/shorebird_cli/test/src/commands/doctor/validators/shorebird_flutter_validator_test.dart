import 'dart:io' hide Platform;

import 'package:collection/collection.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_paths.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockPlatform extends Mock implements Platform {}

void main() {
  group('ShorebirdFlutterValidator', () {
    const gitStatusMessage = """
On branch stable
Your branch is up to date with 'origin/stable'.

nothing to commit, working tree clean
""";

    const gitBranchMessage = '''
  main
* stable
''';

    const pathFlutterVersionMessage = '''
Flutter 3.7.9 • channel unknown • unknown source
Framework • revision 62bd79521d (7 days ago) • 2023-03-30 10:59:36 -0700
Engine • revision ec975089ac
Tools • Dart 2.19.6 • DevTools 2.20.1
''';

    const shorebirdFlutterVersionMessage = '''
Flutter 3.7.9 • channel stable • https://github.com/shorebirdtech/flutter.git
Framework • revision 62bd79521d (7 days ago) • 2023-03-30 10:59:36 -0700
Engine • revision ec975089ac
Tools • Dart 2.19.6 • DevTools 2.20.1
''';

    late ShorebirdFlutterValidator validator;
    late Directory tempDir;
    late ProcessResult pathFlutterVersionProcessResult;
    late ProcessResult shorebirdFlutterVersionProcessResult;
    late ProcessResult gitBranchProcessResult;
    late ProcessResult gitStatusProcessResult;

    Directory flutterDirectory(Directory root) =>
        Directory(p.join(root.path, 'bin', 'cache', 'flutter'));

    File shorebirdScriptFile(Directory root) =>
        File(p.join(root.path, 'bin', 'cache', 'shorebird.snapshot'));

    Directory setupTempDirectory() {
      final tempDir = Directory.systemTemp.createTempSync();
      shorebirdScriptFile(tempDir).createSync(recursive: true);
      flutterDirectory(tempDir).createSync(recursive: true);
      return tempDir;
    }

    setUp(() {
      tempDir = setupTempDirectory();

      ShorebirdPaths.platform = _MockPlatform();
      when(() => ShorebirdPaths.platform.script)
          .thenReturn(shorebirdScriptFile(tempDir).uri);

      pathFlutterVersionProcessResult = _MockProcessResult();
      shorebirdFlutterVersionProcessResult = _MockProcessResult();
      gitBranchProcessResult = _MockProcessResult();
      gitStatusProcessResult = _MockProcessResult();

      validator = ShorebirdFlutterValidator(
        runProcess: (
          executable,
          arguments, {
          bool runInShell = false,
          workingDirectory,
          bool resolveExecutables = true,
        }) async {
          if (executable == 'git') {
            if (arguments.equals(['status'])) {
              return gitStatusProcessResult;
            } else if (arguments.equals(['--no-pager', 'branch'])) {
              return gitBranchProcessResult;
            }
          } else if (executable == 'flutter') {
            if (arguments.equals(['--version'])) {
              if (resolveExecutables) {
                return shorebirdFlutterVersionProcessResult;
              } else {
                return pathFlutterVersionProcessResult;
              }
            }
          }
          return _MockProcessResult();
        },
      );

      when(() => pathFlutterVersionProcessResult.stdout)
          .thenReturn(pathFlutterVersionMessage);
      when(() => shorebirdFlutterVersionProcessResult.stdout)
          .thenReturn(shorebirdFlutterVersionMessage);
      when(() => gitBranchProcessResult.stdout).thenReturn(gitBranchMessage);
      when(() => gitStatusProcessResult.stdout).thenReturn(gitStatusMessage);
    });

    test('returns no issues when the Flutter install is good', () async {
      final results = await validator.validate();

      expect(results, isEmpty);
    });

    test('errors when Flutter does not exist', () async {
      flutterDirectory(tempDir).deleteSync();

      final results = await validator.validate();

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(results.first.message, contains('No Flutter directory found'));
    });

    test('warns when Flutter has local modifications', () async {
      when(() => gitStatusProcessResult.stdout)
          .thenReturn('Changes not staged for commit');

      final results = await validator.validate();

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(results.first.message, contains('has local modifications'));
    });

    test('warns when Flutter does not track stable', () async {
      when(() => gitBranchProcessResult.stdout).thenReturn('''
* main
  stable
''');

      final results = await validator.validate();

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(results.first.message, contains('is not on the "stable" branch'));
    });

    test(
      'warns when path flutter version does not match shorebird flutter'
      ' version',
      () async {
        when(() => pathFlutterVersionProcessResult.stdout).thenReturn(
          pathFlutterVersionMessage.replaceAll('3.7.9', '3.7.10'),
        );

        final results = await validator.validate();

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.warning);
        expect(
          results.first.message,
          contains('Shorebird Flutter and the Flutter on your path are'
              ' different versions'),
        );
      },
    );

    test('throws exception if flutter version output is malformed', () async {
      when(() => pathFlutterVersionProcessResult.stdout)
          .thenReturn('OH NO THERE IS NO FLUTTER VERSION HERE');

      expect(() async => validator.validate(), throwsException);
    });
  });
}
