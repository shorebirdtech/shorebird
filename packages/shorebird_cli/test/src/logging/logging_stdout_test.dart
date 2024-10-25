import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../mocks.dart';

void main() {
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

    test('encoding forwards to baseStdOut', () {
      expect(loggingStdout.encoding, equals(utf8Encoding));
      verify(() => baseStdout.encoding).called(1);
    });

    test('set encoding forwards to baseStdout', () {
      final asciiEncoding = Encoding.getByName('ascii')!;
      loggingStdout.encoding = asciiEncoding;
      verify(() => baseStdout.encoding = asciiEncoding).called(1);
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

    test('set lineTerminator forwards to baseStdout', () {
      loggingStdout.lineTerminator = '\r\n';
      verify(() => baseStdout.lineTerminator = '\r\n').called(1);
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

    test('write forwards to baseStdout, logs to file', () {
      loggingStdout.write('message');
      verify(() => baseStdout.write('message')).called(1);
      expect(logFile.readAsStringSync(), contains('message'));
    });

    test('writeln forwards to baseStdout, logs to file', () {
      loggingStdout.writeln('message');
      verify(() => baseStdout.writeln('message')).called(1);
      expect(logFile.readAsStringSync(), contains('message'));
    });

    test('writeAll forwards to baseStdout, logs to file', () {
      loggingStdout.writeAll(['message']);
      verify(() => baseStdout.writeAll(['message'])).called(1);
      expect(logFile.readAsStringSync(), contains('message'));
    });

    test('writeCharCode forwards to baseStdout, logs as string to file', () {
      loggingStdout.writeCharCode(0);
      verify(() => baseStdout.writeCharCode(0)).called(1);
      expect(logFile.readAsStringSync(), contains('\x00'));
    });
  });
}
