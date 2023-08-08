import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdFlutter extends Mock implements ShorebirdFlutter {}

void main() {
  group(FlutterVersionsUseCommand, () {
    const version = '1.2.3';

    late ArgResults argResults;
    late Progress progress;
    late Logger logger;
    late ShorebirdFlutter shorebirdFlutter;
    late FlutterVersionsUseCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      when(() => argResults.rest).thenReturn([version]);
      progress = _MockProgress();
      logger = _MockLogger();
      shorebirdFlutter = _MockShorebirdFlutter();
      command = runWithOverrides(FlutterVersionsUseCommand.new)
        ..testArgResults = argResults;

      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => shorebirdFlutter.getVersions(),
      ).thenAnswer((_) async => [version]);
      when(
        () => shorebirdFlutter.useVersion(version: any(named: 'version')),
      ).thenAnswer((_) async {});
    });

    test('has correct name and description', () {
      expect(command.name, equals('use'));
      expect(command.description, equals('Use a different Flutter version.'));
    });

    test('exits with code 64 when no version is specified', () async {
      when(() => argResults.rest).thenReturn([]);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.usage.code)),
      );
      verify(
        () => logger.err('''
No version specified.
Usage: shorebird flutter versions use <version>
Use `shorebird flutter versions list` to list available versions.'''),
      ).called(1);
    });

    test('exits with code 64 when too many args are provided', () async {
      when(() => argResults.rest).thenReturn([version, 'foo']);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.usage.code)),
      );
      verify(
        () => logger.err('''
Too many arguments.
Usage: shorebird flutter versions use <version>'''),
      ).called(1);
    });

    test('exits with code 70 when unable to fetch versions', () async {
      when(() => shorebirdFlutter.getVersions()).thenThrow('error');
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => progress.fail('Failed to fetch Flutter versions.'),
        () => logger.err('error'),
      ]);
    });

    test('exits with code 70 when version is not found', () async {
      when(() => shorebirdFlutter.getVersions()).thenAnswer(
        (_) async => ['other-version'],
      );
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => progress.complete(),
        () => logger.err('''
Version $version not found.
Use `shorebird flutter versions list` to list available versions.'''),
      ]);
    });

    test('exits with code 70 when unable to install version', () async {
      when(
        () => shorebirdFlutter.useVersion(version: any(named: 'version')),
      ).thenThrow('error');
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => progress.complete(),
        () => logger.progress('Installing Flutter $version'),
        () => progress.fail('Failed to install Flutter $version.'),
        () => logger.err('error'),
      ]);
    });

    test('exits with code 0 when install succeeds', () async {
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => shorebirdFlutter.getVersions(),
        () => progress.complete(),
        () => logger.progress('Installing Flutter $version'),
        () => shorebirdFlutter.useVersion(version: version),
        () => progress.complete(),
      ]);
    });
  });
}
