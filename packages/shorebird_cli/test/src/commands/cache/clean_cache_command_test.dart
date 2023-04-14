import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCache extends Mock implements Cache {}

void main() {
  group('cache clean', () {
    late Cache cache;
    late Logger logger;
    late CleanCacheCommand cacheCleanCommand;

    setUp(() {
      cache = _MockCache();
      logger = _MockLogger();
      cacheCleanCommand = CleanCacheCommand(cache: cache, logger: logger);
    });

    test('clears the cache', () async {
      final result = await cacheCleanCommand.run();
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.success('✅ Cleared Cache!')).called(1);
      verify(cache.clear).called(1);
    });
  });
}
