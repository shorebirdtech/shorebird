import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

File createTempFile(String name) {
  return File(p.join(Directory.systemTemp.createTempSync().path, name))
    ..createSync();
}

/// Runs [body] while capturing stdout writes into [captured].
///
/// If [hasTerminal] is provided, the captured stdout reports that value for
/// `Stdout.hasTerminal` (otherwise it delegates to the real stdout).
///
/// Used to verify JSON output from commands that write to stdout, and to
/// drive non-interactive code paths in tests.
Future<T> captureStdout<T>(
  Future<T> Function() body, {
  required List<String> captured,
  bool? hasTerminal,
}) async {
  final realStdout = stdout;
  return IOOverrides.runZoned(
    body,
    stdout: () => CapturingStdout(
      baseStdOut: realStdout,
      captured: captured,
      hasTerminalOverride: hasTerminal,
    ),
  );
}

/// A [Stdout] wrapper that captures [writeln] calls into [captured].
class CapturingStdout implements Stdout {
  /// Creates a [CapturingStdout] that delegates to [baseStdOut].
  ///
  /// If [hasTerminalOverride] is non-null, it is returned from [hasTerminal]
  /// instead of delegating — useful for forcing non-interactive code paths.
  CapturingStdout({
    required this.baseStdOut,
    required this.captured,
    this.hasTerminalOverride,
  });

  /// The underlying [Stdout] to delegate to.
  final Stdout baseStdOut;

  /// Lines captured from [writeln] calls.
  final List<String> captured;

  /// If set, [hasTerminal] returns this value instead of delegating.
  final bool? hasTerminalOverride;

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
  bool get hasTerminal => hasTerminalOverride ?? baseStdOut.hasTerminal;

  @override
  IOSink get nonBlocking => baseStdOut.nonBlocking;

  @override
  bool get supportsAnsiEscapes => baseStdOut.supportsAnsiEscapes;

  @override
  int get terminalColumns => baseStdOut.terminalColumns;

  @override
  int get terminalLines => baseStdOut.terminalLines;

  @override
  void add(List<int> data) => baseStdOut.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      baseStdOut.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      baseStdOut.addStream(stream);

  @override
  Future<void> close() => baseStdOut.close();

  @override
  Future<void> flush() => baseStdOut.flush();

  @override
  void write(Object? object) => baseStdOut.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) =>
      baseStdOut.writeAll(objects, sep);

  @override
  void writeCharCode(int charCode) => baseStdOut.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) {
    captured.add(object.toString());
    baseStdOut.writeln(object);
  }
}
