import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdFlutter extends Mock implements ShorebirdFlutter {}

void main() {
  group(FlutterVersionsListCommand, () {
    late Progress progress;
    late Logger logger;
    late ShorebirdFlutter shorebirdFlutter;
    late FlutterVersionsListCommand command;

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
      progress = _MockProgress();
      logger = _MockLogger();
      shorebirdFlutter = _MockShorebirdFlutter();
      command = runWithOverrides(FlutterVersionsListCommand.new);

      when(() => logger.progress(any())).thenReturn(progress);
    });

    test('has correct name and description', () {
      expect(command.name, equals('list'));
      expect(command.description, equals('List available Flutter versions.'));
    });

    test('exits with code 70 when unable to determine Flutter versions',
        () async {
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

    test('exits with code 0 when able to determine Flutter versions', () async {
      const versions = ['1.0.0', '1.0.1'];
      when(
        () => shorebirdFlutter.getVersions(),
      ).thenAnswer((_) async => versions);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => progress.complete(),
        () => logger.info('📦 Flutter Versions'),
        () => logger.info('1.0.1'),
        () => logger.info('1.0.0'),
      ]);
    });
  });
}
