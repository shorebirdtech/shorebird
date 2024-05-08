import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_logger.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group('ShorebirdLogger', () {
    late Directory shorebirdRootDir;
    late ShorebirdEnv shorebirdEnv;
    late Logger logger;
    late ShorebirdLogger shorebirdLogger;

    setUp(() {
      shorebirdRootDir = Directory.systemTemp.createTempSync('shorebird_logs');

      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRootDir);

      logger = MockLogger();
      when(() => logger.theme).thenReturn(const LogTheme());
      shorebirdLogger = ShorebirdLogger(logger: logger);
    });

    String readLogFile() {
      final logFile = Directory(
        p.join(shorebirdRootDir.path, 'logs'),
      ).listSync().first;
      return File(logFile.path).readAsStringSync();
    }

    test('info', () {
      runScoped(
        () {
          shorebirdLogger.info('message');
          verify(() => logger.info('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[INFO] message'));
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
          verify(() => logger.info('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[INFO] MESSAGE'));
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
          verify(() => logger.detail('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[DETAIL] message'));
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
          verify(() => logger.detail('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[DETAIL] MESSAGE'));
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
          verify(() => logger.warn('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[WARN] message'));
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
          verify(() => logger.warn('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[WARN] MESSAGE'));
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
          verify(() => logger.success('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[SUCCESS] message'));
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
          verify(() => logger.success('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[SUCCESS] MESSAGE'));
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
          verify(() => logger.alert('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[ALERT] message'));
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
          verify(() => logger.alert('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[ALERT] MESSAGE'));
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
          verify(() => logger.err('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[ERROR] message'));
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
          verify(() => logger.err('message', style: any(named: 'style')))
              .called(1);
          expect(readLogFile(), contains('[ERROR] MESSAGE'));
        },
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    });
  });
}
