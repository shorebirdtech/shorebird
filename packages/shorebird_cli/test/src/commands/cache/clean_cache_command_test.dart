import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCache extends Mock implements Cache {}

void main() {
  group('cache clean', () {
    late Cache cache;
    late Logger logger;
    late CleanCacheCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    setUp(() {
      cache = _MockCache();
      logger = _MockLogger();
      command = runWithOverrides(() => CleanCacheCommand(cache: cache));
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('clears the cache', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.success('✅ Cleared Cache!')).called(1);
      verify(cache.clear).called(1);
    });
  });
}
