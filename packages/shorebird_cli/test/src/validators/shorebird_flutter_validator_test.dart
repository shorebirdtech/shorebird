import 'dart:io' hide Platform;

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockPlatform extends Mock implements Platform {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group('ShorebirdFlutterValidator', () {
    const flutterRevision = '45fc514f1a9c347a3af76b02baf980a4d88b7879';
    const gitStatusMessage = '''
HEAD detached at 45fc514f
nothing to commit, working tree clean
''';

    const gitRevParseHeadMessage = '''
$flutterRevision
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
    late ProcessResult gitRevParseHeadProcessResult;
    late ProcessResult gitStatusProcessResult;
    late ShorebirdProcess shorebirdProcess;

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

      ShorebirdEnvironment.platform = _MockPlatform();
      ShorebirdEnvironment.flutterRevision = flutterRevision;
      when(() => ShorebirdEnvironment.platform.script)
          .thenReturn(shorebirdScriptFile(tempDir).uri);
      when(() => ShorebirdEnvironment.platform.environment).thenReturn({});

      pathFlutterVersionProcessResult = _MockProcessResult();
      shorebirdFlutterVersionProcessResult = _MockProcessResult();
      gitRevParseHeadProcessResult = _MockProcessResult();
      gitStatusProcessResult = _MockProcessResult();
      shorebirdProcess = _MockShorebirdProcess();

      validator = ShorebirdFlutterValidator();
      when(
        () => shorebirdProcess.run(
          'git',
          ['rev-parse', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => gitRevParseHeadProcessResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['status'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => gitStatusProcessResult);
      when(() => shorebirdProcess.run('flutter', ['--version']))
          .thenAnswer((_) async => shorebirdFlutterVersionProcessResult);
      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--version'],
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => pathFlutterVersionProcessResult);

      when(() => pathFlutterVersionProcessResult.stdout)
          .thenReturn(pathFlutterVersionMessage);
      when(() => pathFlutterVersionProcessResult.stderr).thenReturn('');
      when(() => pathFlutterVersionProcessResult.exitCode).thenReturn(0);
      when(() => shorebirdFlutterVersionProcessResult.stdout)
          .thenReturn(shorebirdFlutterVersionMessage);
      when(() => shorebirdFlutterVersionProcessResult.stderr).thenReturn('');
      when(() => shorebirdFlutterVersionProcessResult.exitCode).thenReturn(0);
      when(() => gitRevParseHeadProcessResult.stdout)
          .thenReturn(gitRevParseHeadMessage);
      when(() => gitStatusProcessResult.stdout).thenReturn(gitStatusMessage);
    });

    test('returns no issues when the Flutter install is good', () async {
      final results = await validator.validate(shorebirdProcess);

      expect(results, isEmpty);
    });

    test('errors when Flutter does not exist', () async {
      flutterDirectory(tempDir).deleteSync();

      final results = await validator.validate(shorebirdProcess);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(results.first.message, contains('No Flutter directory found'));
    });

    test('warns when Flutter has local modifications', () async {
      when(() => gitStatusProcessResult.stdout)
          .thenReturn('Changes not staged for commit');

      final results = await validator.validate(shorebirdProcess);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(results.first.message, contains('has local modifications'));
    });

    test('warns when Flutter does not track stable', () async {
      when(() => gitRevParseHeadProcessResult.stdout).thenReturn('''
62bd79521d
''');

      final results = await validator.validate(shorebirdProcess);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(results.first.message, contains('is not on the correct revision'));
    });

    test(
      'warns when path flutter version does not match shorebird flutter'
      ' version',
      () async {
        when(() => pathFlutterVersionProcessResult.stdout).thenReturn(
          pathFlutterVersionMessage.replaceAll('3.7.9', '3.7.10'),
        );

        final results = await validator.validate(shorebirdProcess);

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.warning);
        expect(
          results.first.message,
          contains(
            'The version of Flutter that Shorebird includes and the Flutter on '
            'your path are different',
          ),
        );
      },
    );

    test(
      'warns if FLUTTER_STORAGE_BASE_URL has a non-empty value',
      () async {
        when(() => ShorebirdEnvironment.platform.environment).thenReturn(
          {'FLUTTER_STORAGE_BASE_URL': 'https://storage.flutter-io.cn'},
        );

        final results = await validator.validate(shorebirdProcess);

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.warning);
        expect(
          results.first.message,
          contains(
            'Shorebird does not respect the FLUTTER_STORAGE_BASE_URL '
            'environment variable',
          ),
        );
      },
    );

    test('throws exception if flutter version output is malformed', () async {
      when(() => pathFlutterVersionProcessResult.stdout)
          .thenReturn('OH NO THERE IS NO FLUTTER VERSION HERE');

      expect(() async => validator.validate(shorebirdProcess), throwsException);
    });

    test('prints stderr output and throws if version check fails', () async {
      when(() => pathFlutterVersionProcessResult.exitCode).thenReturn(1);
      when(() => pathFlutterVersionProcessResult.stderr)
          .thenReturn('error getting Flutter version');

      expect(
        () async => validator.validate(shorebirdProcess),
        throwsA(
          isA<FlutterValidationException>().having(
            (e) => e.message,
            'message',
            contains('error getting Flutter version'),
          ),
        ),
      );
    });
  });
}
