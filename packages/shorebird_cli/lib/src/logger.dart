import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [Logger] instance.
final loggerRef = create(ShorebirdLogger.new);

/// The [Logger] instance available in the current zone.
ShorebirdLogger get logger => read(loggerRef);

const _logFileName = 'shorebird.log';

/// Where logs are written for the current Shorebird CLI run. A new file will
/// be created for every run of the Shorebird CLI, and will have the name
/// `timestamp_shorebird.log`.
final File currentRunLogFile = (() {
  // TODO(bryanoltman): use package:clock to test for the correct timestamp
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final file = File(
    p.join(
      shorebirdEnv.logsDirectory.path,
      '${timestamp}_$_logFileName',
    ),
  );

  if (!file.existsSync()) {
    file.createSync(recursive: true);
  }

  return file;
})();

/// Writes the given [message] to the [logFile] on its own line, prefixed with
/// the current timestamp.
void _writeToLogFile(Object? message, {required File logFile}) {
  if (message == null) {
    return;
  }

  // Making sure the log file exists before writing to it.
  // This is necessary because the log file may be deleted by a cache
  // clear command.
  if (!logFile.existsSync()) return;

  final timestampString = DateTime.now().toIso8601String();
  final messageString = message.toString().removeAnsiEscapes();
  logFile.writeAsStringSync(
    '$timestampString $messageString\n',
    mode: FileMode.append,
  );
}

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
    _writeToLogFile(object, logFile: logFile);
  }
}

/// {@template shorebird_logger}
/// A [Logger] that
/// {@endtemplate}
class ShorebirdLogger extends Logger {
  /// {@macro shorebird_logger}
  ShorebirdLogger({super.level});

  @override
  void detail(String? message, {LogStyle? style}) {
    super.detail(message, style: style);
    if (level.index > Level.debug.index) {
      // We only need to write the message to the log file if this will not
      // be written to stdout. If it is written to stdout, [LoggingStdout] will
      // written to the log file.
      _writeToLogFile(message ?? '', logFile: currentRunLogFile);
    }
  }
}
