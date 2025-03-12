import 'dart:io';

import 'package:clock/clock.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('currentRunLogFile', () {
    late ShorebirdEnv shorebirdEnv;
    late Directory logsDirectory;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
    }

    setUp(() {
      logsDirectory = Directory.systemTemp.createTempSync('shorebird_logs');
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.logsDirectory).thenReturn(logsDirectory);
    });

    test('creates a log file in the logs directory', () {
      final date = DateTime(2021);
      final file = withClock(
        Clock.fixed(date),
        () => runWithOverrides(() => currentRunLogFile),
      );
      expect(file.existsSync(), isTrue);
      expect(
        file.path,
        equals(
          p.join(
            logsDirectory.path,
            '${date.millisecondsSinceEpoch}_shorebird.log',
          ),
        ),
      );
    });
  });

  group(ShorebirdLogger, () {
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
    }

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      when(
        () => shorebirdEnv.logsDirectory,
      ).thenReturn(Directory.systemTemp.createTempSync());
      logger = ShorebirdLogger();
    });

    group('detail', () {
      group('when log level is debug or higher', () {
        setUp(() {
          logger.level = Level.debug;
        });

        test('does not write message to log file', () {
          const message = 'my detail message';
          logger.detail(message);
          expect(
            // Replacing this with a tear-off influences
            // ignore: unnecessary_lambdas
            runWithOverrides(() => currentRunLogFile.readAsStringSync()),
            isNot(contains(message)),
          );
        });
      });

      group('when log level is lower than debug', () {
        setUp(() {
          logger.level = Level.info;
        });

        test('writes message to log file', () {
          const message = 'my detail message';
          logger.detail(message);
          expect(
            // Replacing this with a tear-off influences
            // ignore: unnecessary_lambdas
            runWithOverrides(() => currentRunLogFile.readAsStringSync()),
            contains(message),
          );
        });
      });
    });
  });
}
