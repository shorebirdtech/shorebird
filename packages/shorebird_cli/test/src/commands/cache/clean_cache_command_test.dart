import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group('run', () {
    late ArgResults argResults;
    late Directory applicationConfigHome;
    late Logger logger;
    late CleanCacheCommand cacheCleanCommand;

    setUp(() {
      argResults = _MockArgResults();
      applicationConfigHome = Directory.systemTemp.createTempSync();
      logger = _MockLogger();
      cacheCleanCommand = CleanCacheCommand(
        logger: logger,
      )..testArgResults = argResults;

      //TODO: `shorebirdConfigDir` points to a real path
      // instead of this test path.
      testApplicationConfigHome = (_) => applicationConfigHome.path;
    });

    test('cache is already clean', () async {
      final result = await cacheCleanCommand.run();
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('The cache is already clean.')).called(1);
    });

    test('clean cache', () async {
      Directory(
        p.join(applicationConfigHome.path, 'engines', 'testEngine'),
      ).createSync(recursive: true);

      final result = await cacheCleanCommand.run();
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.success('Successfully cleaned the cache!')).called(1);
    });
  });
}
