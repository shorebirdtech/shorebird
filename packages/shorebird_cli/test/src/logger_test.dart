import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group('currentRunLogFile', () {
    late ShorebirdEnv shorebirdEnv;
    late Directory logsDirectory;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      logsDirectory = Directory.systemTemp.createTempSync('shorebird_logs');
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.logsDirectory).thenReturn(logsDirectory);
    });

    test('creates a log file in the logs directory', () {
      final file = runWithOverrides(() => currentRunLogFile);
      expect(file.existsSync(), isTrue);
      expect(file.path, startsWith(logsDirectory.path));
    });
  });

  group(LoggingStdout, () {
    final utf8Encoding = Encoding.getByName('utf-8')!;
    late File logFile;
    late LoggingStdout loggingStdout;
    late Stdout baseStdout;

    setUpAll(() {
      registerFallbackValue(const Stream<List<int>>.empty());
    });

    setUp(() {
      final tempDir = Directory.systemTemp.createTempSync('shorebird_logs');
      logFile = File(p.join(tempDir.path, 'shorebird.log'));
      baseStdout = MockStdout();

      when(() => baseStdout.addStream(any())).thenAnswer((_) async {});
      when(() => baseStdout.close()).thenAnswer((_) async {});
      when(() => baseStdout.done).thenAnswer((_) async {});
      when(() => baseStdout.encoding).thenReturn(utf8Encoding);
      when(() => baseStdout.flush()).thenAnswer((_) async {});
      when(() => baseStdout.hasTerminal).thenReturn(true);
      when(() => baseStdout.lineTerminator).thenReturn('\n');
      when(() => baseStdout.nonBlocking).thenReturn(FakeIOSink());
      when(() => baseStdout.supportsAnsiEscapes).thenReturn(false);
      when(() => baseStdout.terminalColumns).thenReturn(80);
      when(() => baseStdout.terminalLines).thenReturn(40);

      loggingStdout = LoggingStdout(baseStdOut: baseStdout, logFile: logFile);
    });

    test('forwards encoding from baseStdOut', () {
      expect(loggingStdout.encoding, equals(utf8Encoding));
    });

    test('addStream forwards to baseStdout', () async {
      final stream = Stream.fromIterable(['message'.codeUnits]);
      await loggingStdout.addStream(stream);
      verify(() => baseStdout.addStream(stream)).called(1);
    });

    test('close forwards to baseStdout', () async {
      await loggingStdout.close();
      verify(() => baseStdout.close()).called(1);
    });

    test('done forwards to baseStdout', () async {
      await loggingStdout.done;
      verify(() => baseStdout.done).called(1);
    });

    test('flush forwards to baseStdout', () async {
      await loggingStdout.flush();
      verify(() => baseStdout.flush()).called(1);
    });

    test('hasTerminal forwards to baseStdout', () {
      expect(loggingStdout.hasTerminal, isTrue);
      verify(() => baseStdout.hasTerminal).called(1);
    });

    test('lineTerminator forwards to baseStdout', () {
      expect(loggingStdout.lineTerminator, equals('\n'));
      verify(() => baseStdout.lineTerminator).called(1);
    });

    test('nonBlocking forwards to baseStdout', () {
      expect(loggingStdout.nonBlocking, isA<FakeIOSink>());
      verify(() => baseStdout.nonBlocking).called(1);
    });

    test('supportsAnsiEscapes forwards to baseStdout', () {
      expect(loggingStdout.supportsAnsiEscapes, isFalse);
      verify(() => baseStdout.supportsAnsiEscapes).called(1);
    });

    test('terminalColumns forwards to baseStdout', () {
      expect(loggingStdout.terminalColumns, equals(80));
      verify(() => baseStdout.terminalColumns).called(1);
    });

    test('terminalLines forwards to baseStdout', () {
      expect(loggingStdout.terminalLines, equals(40));
      verify(() => baseStdout.terminalLines).called(1);
    });

    test('add forwards to baseStdout, logs to file', () {
      loggingStdout.add('message'.codeUnits);
      verify(() => baseStdout.add('message'.codeUnits)).called(1);
      expect(logFile.readAsStringSync(), contains('message'));
    });

    test('addError forwards to baseStdout, logs to file', () {
      loggingStdout.addError('error');
      verify(() => baseStdout.addError('error')).called(1);
      expect(logFile.readAsStringSync(), contains('error'));
    });

    test('addError with stack trace forwards to baseStdout, logs to file', () {
      loggingStdout.addError('error', StackTrace.current);
      verify(() => baseStdout.addError('error', any())).called(1);
      expect(logFile.readAsStringSync(), contains('error'));
      expect(
        logFile.readAsStringSync(),
        contains('#0      main.<anonymous closure>.<anonymous closure>'),
      );
    });

    test('forwards write to baseStdout, logs to file', () {
      loggingStdout.write('message');
      verify(() => baseStdout.write('message')).called(1);
      expect(logFile.readAsStringSync(), contains('message'));
    });

    test('forwards writeln to baseStdout, logs to file', () {
      loggingStdout.writeln('message');
      verify(() => baseStdout.writeln('message')).called(1);
      expect(logFile.readAsStringSync(), contains('message'));
    });

    test('forwards writeAll to baseStdout, logs to file', () {
      loggingStdout.writeAll(['message']);
      verify(() => baseStdout.writeAll(['message'])).called(1);
      expect(logFile.readAsStringSync(), contains('message'));
    });

    test('forwards writeCharCode to baseStdout, logs as string to file', () {
      loggingStdout.writeCharCode(0);
      verify(() => baseStdout.writeCharCode(0)).called(1);
      expect(logFile.readAsStringSync(), contains('\x00'));
    });
  });

  group(ShorebirdLogger, () {
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.logsDirectory).thenReturn(
        Directory.systemTemp.createTempSync(),
      );
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
