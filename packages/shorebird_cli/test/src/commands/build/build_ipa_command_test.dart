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
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(BuildIpaCommand, () {
    late ArgResults argResults;
    late Doctor doctor;
    late Logger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late ShorebirdProcessResult buildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
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
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeShorebirdProcess());
    });

    setUp(() {
      argResults = MockArgResults();
      doctor = MockDoctor();
      logger = MockLogger();
      operatingSystemInterface = MockOperatingSystemInterface();
      shorebirdProcess = MockShorebirdProcess();
      buildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdValidator = MockShorebirdValidator();

      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => flutterPubGetProcessResult);
      when(() => flutterPubGetProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => buildProcessResult);
      when(() => argResults['codesign']).thenReturn(true);
      when(() => argResults.rest).thenReturn([]);
      when(() => logger.progress(any())).thenReturn(MockProgress());
      when(() => logger.info(any())).thenReturn(null);
      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
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
      when(() => buildProcessResult.exitCode).thenReturn(1);
      when(() => buildProcessResult.stderr).thenReturn('oops');
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
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
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

    test('runs flutter pub get with system flutter after successful build',
        () async {
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
      final tempDir = Directory.systemTemp.createTempSync();

      await IOOverrides.runZoned(
        () async => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).called(1);
    });

    test(
        'exits with code 0 when building ipa succeeds '
        'with flavor and target', () async {
      const flavor = 'development';
      final target = p.join('lib', 'main_development.dart');
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
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
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
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
      when(() => buildProcessResult.exitCode).thenReturn(ExitCode.success.code);
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
