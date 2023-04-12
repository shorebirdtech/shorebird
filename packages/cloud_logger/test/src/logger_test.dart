import 'dart:async';

import 'package:cloud_logger/src/cloud_logger.dart';
import 'package:cloud_logger/src/logger.dart';
import 'package:test/test.dart';

import '../helpers/helpers.dart';

void main() {
  group('LogSeverity', () {
    test('compareTo', () {
      expect(LogSeverity.info.compareTo(LogSeverity.info), equals(0));
      expect(LogSeverity.info.compareTo(LogSeverity.debug), equals(1));
    });

    test('toString', () {
      expect(LogSeverity.info.toString(), equals('LogSeverity INFO (200)'));
    });
  });

  group('logger', () {
    test(
      'prints correctly formatted log entry (default)',
      overridePrint((logs) {
        expect(logs, isEmpty);
        logger
          ..info('info')
          ..debug('debug')
          ..notice('notice')
          ..warning('warning')
          ..error('error')
          ..critical('critical')
          ..alert('alert')
          ..emergency('emergency');

        expect(
          logs,
          equals([
            '[INFO]: info',
            '[DEBUG]: debug',
            '[NOTICE]: notice',
            '[WARNING]: warning',
            '[ERROR]: error',
            '[CRITICAL]: critical',
            '[ALERT]: alert',
            '[EMERGENCY]: emergency',
          ]),
        );
      }),
    );

    test(
      'prints correctly formatted log entry (cloud)',
      overridePrint((logs) {
        const traceId = '0679686673a';
        Zone.current.fork(
          zoneValues: {loggerKey: CloudLogger(Zone.current, traceId)},
        ).run(() {
          expect(logs, isEmpty);

          logger
            ..info('info')
            ..debug('debug')
            ..notice('notice')
            ..warning('warning')
            ..error('error')
            ..critical('critical')
            ..alert('alert')
            ..emergency('emergency');
        });

        expect(
          logs,
          equals([
            '{"message":"info","severity":"INFO","logging.googleapis.com/trace":"$traceId"}',
            '{"message":"debug","severity":"DEBUG","logging.googleapis.com/trace":"$traceId"}',
            '{"message":"notice","severity":"NOTICE","logging.googleapis.com/trace":"$traceId"}',
            '{"message":"warning","severity":"WARNING","logging.googleapis.com/trace":"$traceId"}',
            '{"message":"error","severity":"ERROR","logging.googleapis.com/trace":"$traceId"}',
            '{"message":"critical","severity":"CRITICAL","logging.googleapis.com/trace":"$traceId"}',
            '{"message":"alert","severity":"ALERT","logging.googleapis.com/trace":"$traceId"}',
            '{"message":"emergency","severity":"EMERGENCY","logging.googleapis.com/trace":"$traceId"}'
          ]),
        );
      }),
    );
  });
}
