import 'dart:io' hide Platform;

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter_manager.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockPlatform extends Mock implements Platform {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdFlutterManager extends Mock
    implements ShorebirdFlutterManager {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(ShorebirdFlutterValidator, () {
    const flutterRevision = '45fc514f1a9c347a3af76b02baf980a4d88b7879';

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
    late ShorebirdProcessResult pathFlutterVersionProcessResult;
    late ShorebirdProcessResult shorebirdFlutterVersionProcessResult;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutterManager shorebirdFlutterManager;
    late Platform platform;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterManagerRef.overrideWith(
            () => shorebirdFlutterManager,
          ),
        },
      );
    }

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
      platform = _MockPlatform();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdFlutterManager = _MockShorebirdFlutterManager();

      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdEnv.flutterDirectory,
      ).thenReturn(flutterDirectory(tempDir));
      when(() => platform.script).thenReturn(shorebirdScriptFile(tempDir).uri);
      when(() => platform.environment).thenReturn({});

      pathFlutterVersionProcessResult = _MockProcessResult();
      shorebirdFlutterVersionProcessResult = _MockProcessResult();
      shorebirdProcess = _MockShorebirdProcess();

      validator = ShorebirdFlutterValidator();
      when(
        () => shorebirdFlutterManager.isPorcelain(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--version'],
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => shorebirdFlutterVersionProcessResult);
      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--version'],
          useVendedFlutter: false,
          runInShell: any(named: 'runInShell'),
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
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    test('canRunInContext always returns true', () {
      expect(validator.canRunInCurrentContext(), isTrue);
    });

    test('returns no issues when the Flutter install is good', () async {
      final results = await runWithOverrides(validator.validate);

      expect(results, isEmpty);
    });

    test('errors when Flutter does not exist', () async {
      flutterDirectory(tempDir).deleteSync();

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(results.first.message, contains('No Flutter directory found'));
    });

    test('warns when Flutter has local modifications', () async {
      when(
        () => shorebirdFlutterManager.isPorcelain(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => false);

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(results.first.message, contains('has local modifications'));
    });

    test(
      'does not warn if flutter version and shorebird flutter version have same'
      ' major and minor but different patch versions',
      () async {
        when(() => pathFlutterVersionProcessResult.stdout).thenReturn(
          pathFlutterVersionMessage.replaceAll('3.7.9', '3.7.10'),
        );

        final results = await runWithOverrides(
          () => validator.validate(),
        );

        expect(results, isEmpty);
      },
    );

    test(
      'warns when path flutter version has different major or minor version '
      'than shorebird flutter',
      () async {
        when(() => pathFlutterVersionProcessResult.stdout).thenReturn(
          pathFlutterVersionMessage.replaceAll('3.7.9', '3.8.9'),
        );

        final results = await runWithOverrides(validator.validate);

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
        when(() => platform.environment).thenReturn(
          {'FLUTTER_STORAGE_BASE_URL': 'https://storage.flutter-io.cn'},
        );

        final results = await runWithOverrides(validator.validate);

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

    test('throws exception if path flutter version output is malformed',
        () async {
      when(() => pathFlutterVersionProcessResult.stdout)
          .thenReturn('OH NO THERE IS NO FLUTTER VERSION HERE');

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(
        results[0],
        isA<ValidationIssue>().having(
          (exception) => exception.message,
          'message',
          contains('Failed to determine path Flutter version'),
        ),
      );
    });

    test('prints stderr output and throws if path Flutterversion check fails',
        () async {
      when(() => pathFlutterVersionProcessResult.exitCode).thenReturn(1);
      when(() => pathFlutterVersionProcessResult.stderr)
          .thenReturn('error getting Flutter version');

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(
        results[0],
        isA<ValidationIssue>().having(
          (exception) => exception.message,
          'message',
          contains('Failed to determine path Flutter version'),
        ),
      );
    });

    test('throws exception if shorebird flutter version output is malformed',
        () async {
      when(() => shorebirdFlutterVersionProcessResult.stdout)
          .thenReturn('OH NO THERE IS NO FLUTTER VERSION HERE');

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(
        results[0],
        isA<ValidationIssue>().having(
          (exception) => exception.message,
          'message',
          contains('Failed to determine Shorebird Flutter version'),
        ),
      );
    });

    test('prints stderr output and throws if path Flutterversion check fails',
        () async {
      when(() => shorebirdFlutterVersionProcessResult.exitCode).thenReturn(1);
      when(() => shorebirdFlutterVersionProcessResult.stderr)
          .thenReturn('error getting Flutter version');

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(
        results[0],
        isA<ValidationIssue>().having(
          (exception) => exception.message,
          'message',
          contains('Failed to determine Shorebird Flutter version'),
        ),
      );
    });
  });
}
