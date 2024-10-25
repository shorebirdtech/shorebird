import 'dart:convert';
import 'dart:io';

import 'package:shorebird_cli/src/extensions/string.dart';

/// {@template logging_stdout}
/// A [Stdout] implementation that logs output to a file after forwarding
/// methods to a wrapped [Stdout] instance ([baseStdOut]). This is intended to
/// be used as an IOOverrides.stdout implementation to log all stdout output
/// to a file.
///
/// Example:
///  ```dart
///   final loggingStdout = LoggingStdout(baseStdOut: stdout, logFile: logFile);
///   IOOverrides.runZoned(
///    () => myCode(),
///    stdout: loggingStdout,
///   );
/// ```
/// {@endtemplate}
class LoggingStdout implements Stdout {
  /// {@macro logging_stdout}
  LoggingStdout({required this.baseStdOut, required this.logFile});

  /// The underlying [Stdout] instance that method calls are forwarded to.
  final Stdout baseStdOut;

  /// The file to which all stdout output is appended. Must exist.
  final File logFile;

  @override
  Encoding get encoding => baseStdOut.encoding;

  @override
  set encoding(Encoding value) => baseStdOut.encoding = value;

  @override
  String get lineTerminator => baseStdOut.lineTerminator;

  @override
  set lineTerminator(String value) => baseStdOut.lineTerminator = value;

  @override
  Future<void> get done => baseStdOut.done;

  @override
  bool get hasTerminal => baseStdOut.hasTerminal;

  @override
  IOSink get nonBlocking => baseStdOut.nonBlocking;

  @override
  bool get supportsAnsiEscapes => baseStdOut.supportsAnsiEscapes;

  @override
  int get terminalColumns => baseStdOut.terminalColumns;

  @override
  int get terminalLines => baseStdOut.terminalLines;

  @override
  void add(List<int> data) {
    baseStdOut.add(data);
    _writeLog(String.fromCharCodes(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    baseStdOut.addError(error, stackTrace);

    if (stackTrace == null) {
      _writeLog(error);
    } else {
      _writeLog('$error\n$stackTrace');
    }
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      baseStdOut.addStream(stream);

  @override
  Future<void> close() => baseStdOut.close();

  @override
  Future<void> flush() => baseStdOut.flush();

  @override
  void write(Object? object) {
    baseStdOut.write(object);
    _writeLog(object);
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) {
    baseStdOut.writeAll(objects, sep);
    _writeLog(objects);
  }

  @override
  void writeCharCode(int charCode) {
    baseStdOut.writeCharCode(charCode);
    _writeLog(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    baseStdOut.writeln(object);
    _writeLog(object);
  }

  void _writeLog(Object? object) {
    writeToLogFile(object, logFile: logFile);
  }
}

/// Writes the given [message] to the [logFile] on its own line, prefixed with
/// the current timestamp.
void writeToLogFile(Object? message, {required File logFile}) {
  if (message == null) {
    return;
  }

  final timestampString = DateTime.now().toIso8601String();
  final messageString = message.toString().removeAnsiEscapes();
  logFile.writeAsStringSync(
    '$timestampString $messageString\n',
    mode: FileMode.append,
  );
}
