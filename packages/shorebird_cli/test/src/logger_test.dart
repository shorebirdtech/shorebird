import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group('ShorebirdLogger', () {
    late Directory shorebirdConfigDir;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger shorebirdLogger;

    setUp(() {
      shorebirdConfigDir = Directory.systemTemp.createTempSync(
        'shorebird_config',
      );

      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.configDirectory).thenReturn(shorebirdConfigDir);

      // Setting to quiet so we don't spam the stdout/stderr while testing
      shorebirdLogger = ShorebirdLogger(level: Level.quiet);
    });

    String readLogFile() {
      final logFile = Directory(
        p.join(shorebirdConfigDir.path, 'logs'),
      ).listSync().first;
      return File(logFile.path).readAsStringSync();
    }

    test('can be instantiated', () {
      expect(
        ShorebirdLogger.new,
        returnsNormally,
      );
    });

    test('info', () {
      runScoped(
        () {
          shorebirdLogger.info('message');
          expect(readLogFile(), contains('[INFO]'));
          expect(readLogFile(), contains('message'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('info with style', () {
      runScoped(
        () {
          shorebirdLogger.info(
            'message',
            style: (message) => message?.toUpperCase(),
          );
          expect(readLogFile(), contains('[INFO]'));
          expect(readLogFile(), contains('MESSAGE'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('detail', () {
      runScoped(
        () {
          shorebirdLogger.detail('message');
          expect(readLogFile(), contains('[DETAIL]'));
          expect(readLogFile(), contains('message'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('detail with style', () {
      runScoped(
        () {
          shorebirdLogger.detail(
            'message',
            style: (message) => message?.toUpperCase(),
          );
          expect(readLogFile(), contains('[DETAIL]'));
          expect(readLogFile(), contains('MESSAGE'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('warn', () {
      runScoped(
        () {
          shorebirdLogger.warn('message');
          expect(readLogFile(), contains('[WARN]'));
          expect(readLogFile(), contains('message'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('warn with style', () {
      runScoped(
        () {
          shorebirdLogger.warn(
            'message',
            style: (message) => message?.toUpperCase(),
          );
          expect(readLogFile(), contains('[WARN]'));
          expect(readLogFile(), contains('MESSAGE'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('success', () {
      runScoped(
        () {
          shorebirdLogger.success('message');
          expect(readLogFile(), contains('[SUCCESS]'));
          expect(readLogFile(), contains('message'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('success with style', () {
      runScoped(
        () {
          shorebirdLogger.success(
            'message',
            style: (message) => message?.toUpperCase(),
          );
          expect(readLogFile(), contains('[SUCCESS]'));
          expect(readLogFile(), contains('MESSAGE'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('alert', () {
      runScoped(
        () {
          shorebirdLogger.alert('message');
          expect(readLogFile(), contains('[ALERT]'));
          expect(readLogFile(), contains('message'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('alert with style', () {
      runScoped(
        () {
          shorebirdLogger.alert(
            'message',
            style: (message) => message?.toUpperCase(),
          );
          expect(readLogFile(), contains('[ALERT]'));
          expect(readLogFile(), contains('MESSAGE'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('err', () {
      runScoped(
        () {
          shorebirdLogger.err('message');
          expect(readLogFile(), contains('[ERROR]'));
          expect(readLogFile(), contains('message'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });

    test('err with style', () {
      runScoped(
        () {
          shorebirdLogger.err(
            'message',
            style: (message) => message?.toUpperCase(),
          );
          expect(readLogFile(), contains('[ERROR]'));
          expect(readLogFile(), contains('MESSAGE'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });
  });
}
