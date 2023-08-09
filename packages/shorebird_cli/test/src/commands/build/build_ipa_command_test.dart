import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockDoctor extends Mock implements Doctor {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

class _FakeShorebirdProcess extends Fake implements ShorebirdProcess {}

void main() {
  group(BuildIpaCommand, () {
    late ArgResults argResults;
    late Doctor doctor;
    late Logger logger;
    late ShorebirdProcessResult processResult;
    late BuildIpaCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(_FakeShorebirdProcess());
    });

    setUp(() {
      argResults = _MockArgResults();
      doctor = _MockDoctor();
      logger = _MockLogger();
      shorebirdProcess = _MockShorebirdProcess();
      processResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdValidator = _MockShorebirdValidator();

      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => processResult);
      when(() => argResults['codesign']).thenReturn(true);
      when(() => argResults.rest).thenReturn([]);
      when(() => logger.progress(any())).thenReturn(_MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(BuildIpaCommand.new)
        ..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
          checkShorebirdInitialized: true,
          validators: [flutterValidator],
        ),
      ).called(1);
    });

    test('exits with code 70 when building ipa fails', () async {
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn('oops');
      final tempDir = Directory.systemTemp.createTempSync();

      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          any(
            that: containsAll(
              ['build', 'ipa', '--release'],
            ),
          ),
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
    });

    test('exits with code 0 when building ipa succeeds', () async {
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          any(
            that: containsAll(
              ['build', 'ipa', '--release'],
            ),
          ),
          runInShell: true,
        ),
      ).called(1);

      verifyInOrder([
        () => logger.info(
              '''
📦 Generated an xcode archive at:
${lightCyan.wrap(p.join('build', 'ios', 'archive', 'Runner.xcarchive'))}''',
            ),
        () => logger.info(
              '''
📦 Generated an ipa at:
${lightCyan.wrap(p.join('build', 'ios', 'ipa', 'Runner.ipa'))}''',
            ),
      ]);
    });

    test(
        'exits with code 0 when building ipa succeeds '
        'with flavor and target', () async {
      const flavor = 'development';
      final target = p.join('lib', 'main_development.dart');
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          any(
            that: containsAll(
              [
                'build',
                'ipa',
                '--release',
                '--flavor=$flavor',
                '--target=$target',
              ],
            ),
          ),
          runInShell: true,
        ),
      ).called(1);

      verifyInOrder([
        () => logger.info(
              '''
📦 Generated an xcode archive at:
${lightCyan.wrap(p.join('build', 'ios', 'archive', 'Runner.xcarchive'))}''',
            ),
        () => logger.info(
              '''
📦 Generated an ipa at:
${lightCyan.wrap(p.join('build', 'ios', 'ipa', 'Runner.ipa'))}''',
            ),
      ]);
    });

    test(
        'exits with code 0 when building ipa succeeds '
        'with --no-codesign', () async {
      when(() => argResults['codesign']).thenReturn(false);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          any(
            that: containsAll(['build', 'ipa', '--release', '--no-codesign']),
          ),
          runInShell: true,
        ),
      ).called(1);

      verify(
        () => logger.info(
          '''
📦 Generated an xcode archive at:
${lightCyan.wrap(p.join('build', 'ios', 'archive', 'Runner.xcarchive'))}''',
        ),
      ).called(1);

      verifyNever(
        () => logger.info(
          '''
📦 Generated an ipa at:
${lightCyan.wrap(p.join('build', 'ios', 'ipa', 'Runner.ipa'))}''',
        ),
      );
    });

    test('provides appropriate ExportOptions.plist to build ipa command',
        () async {
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();
      final result = await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.success.code));
      expect(exitCode, ExitCode.success.code);
      final capturedArgs = verify(
        () => shorebirdProcess.run(
          'flutter',
          captureAny(),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured.first as List<String>;
      final exportOptionsPlistFile = File(
        capturedArgs
            .whereType<String>()
            .firstWhere((arg) => arg.contains('export-options-plist'))
            .split('=')
            .last,
      );
      expect(exportOptionsPlistFile.existsSync(), isTrue);
      final exportOptionsPlist =
          PropertyListSerialization.propertyListWithString(
        exportOptionsPlistFile.readAsStringSync(),
      ) as Map<String, Object>;
      expect(exportOptionsPlist['manageAppVersionAndBuildNumber'], isFalse);
      expect(exportOptionsPlist['signingStyle'], 'automatic');
      expect(exportOptionsPlist['uploadBitcode'], isFalse);
      expect(exportOptionsPlist['method'], 'app-store');
    });
  });
}
