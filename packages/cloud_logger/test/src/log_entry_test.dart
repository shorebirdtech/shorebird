import 'package:cloud_logger/cloud_logger.dart';
import 'package:cloud_logger/src/log_entry.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

void main() {
  const traceValue = '0679686673a';
  const message = 'hello world';

  group('createLogEntry', () {
    test('returns correctly formatted log entry', () {
      final frame =
          Chain.forTrace(StackTrace.current).traces.first.frames.first;
      final entry = createLogEntry(
        traceValue,
        message,
        LogSeverity.info,
        stackFrame: frame,
      );
      expect(
        entry,
        startsWith(
          '{"message":"hello world","severity":"INFO","logging.googleapis.com/trace":"0679686673a","logging.googleapis.com/sourceLocation":{"file":"test/src/log_entry_test.dart',
        ),
      );
    });
  });

  group('createErrorLogEntry', () {
    test('returns correctly formatted log entry', () {
      final entry = createErrorLogEntry(
        'error',
        traceValue,
        StackTrace.current,
        LogSeverity.error,
      );
      expect(
        entry,
        contains(r'"message":"error\ntest/src/log_entry_test.dart'),
      );
      expect(entry, contains('"severity":"ERROR"'));
      expect(entry, contains('"logging.googleapis.com/trace":"0679686673a"'));
    });
  });
}
