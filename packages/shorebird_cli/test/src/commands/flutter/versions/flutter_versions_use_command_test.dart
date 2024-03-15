import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

import '../../../mocks.dart';

void main() {
  group(FlutterVersionsUseCommand, () {
    const version = '1.2.3';
    const revision = '0fc414cbc33ee017ad509671009e8b242539ea16';

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
      argResults = MockArgResults();
      when(() => argResults.rest).thenReturn([version]);
      progress = MockProgress();
      logger = MockLogger();
      shorebirdFlutter = MockShorebirdFlutter();
      command = runWithOverrides(FlutterVersionsUseCommand.new)
        ..testArgResults = argResults;

      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => shorebirdFlutter.getVersions(),
      ).thenAnswer((_) async => [version]);
      when(
        () => shorebirdFlutter.useVersion(version: any(named: 'version')),
      ).thenAnswer((_) async {});
      when(
        () => shorebirdFlutter.useRevision(revision: any(named: 'revision')),
      ).thenAnswer((_) async {});
    });

    test('has correct name and description', () {
      expect(command.name, equals('use'));
      expect(command.description, equals('Use a different Flutter version.'));
    });

    test('logs deprecation warning', () async {
      await runWithOverrides(command.run);
      verify(
        () => logger.warn(
          '''
This command has been deprecated and will be removed in the next major version.
Please use: "shorebird release <target> --flutter-version <version>" instead.
''',
        ),
      ).called(1);
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
      final openIssueLink = link(
        uri: Uri.parse(
          'https://github.com/shorebirdtech/shorebird/issues/new?assignees=&labels=feature&projects=&template=feature_request.md&title=feat%3A+',
        ),
        message: 'open an issue',
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => progress.complete(),
        () => logger.err('''
Version $version not found. Please $openIssueLink to request a new version.
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
      ]);
    });

    test('exits with code 70 when unable to install revision', () async {
      when(() => argResults.rest).thenReturn([revision]);
      when(
        () => shorebirdFlutter.useRevision(revision: any(named: 'revision')),
      ).thenThrow('error');
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );
    });

    test('exits with code 0 when version install succeeds', () async {
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => shorebirdFlutter.getVersions(),
        () => progress.complete(),
      ]);
    });

    test('exits with code 0 when revision install succeeds', () async {
      when(() => argResults.rest).thenReturn([revision]);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );
    });
  });
}
