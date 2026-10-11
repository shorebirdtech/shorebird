import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:test/test.dart';

/// An operating system shorebird_cli has no platform-specific handling for.
///
/// Use as a [NativePlatform.operatingSystem] so `isLinux`, `isMacOS` and
/// `isWindows` are all false until a test picks one.
const unsupportedOperatingSystem = NativePlatform.fuchsia;

/// Makes relative paths in this test file resolve into a new temporary
/// directory rather than this package.
///
/// `dart test` runs from the package directory, so a path a test makes up,
/// such as `File('')` or `File('path/to/file')`, names a real place in the
/// developer's checkout. Code under test that deletes a parent of such a path
/// would delete the checkout. Every test file calls this first in `main`, and
/// `test/temp_working_directory_test.dart` enforces that.
///
/// This installs an [IOOverrides.global] instead of setting
/// [Directory.current], because the working directory belongs to the whole
/// process: test files run concurrently in isolates of one process, and the
/// test runner resolves paths such as its coverage output against it. The
/// overrides are per isolate, and so per test file.
///
/// Read files checked in to this package with [packagePath] or
/// [fixturesDirectory].
void useTempWorkingDirectory() {
  // A runner that bundles test files into one isolate calls this once per
  // file, and by the second call the current directory is a temporary one.
  _packageDirectory ??= Directory.current.path;
  final root = Directory.systemTemp.createTempSync('shorebird_cli_test_');
  // Nested, so that `File('').parent` is still a directory this file owns.
  final workingDirectory = Directory(p.join(root.path, 'cwd'))..createSync();
  IOOverrides.global = _TempWorkingDirectoryOverrides(workingDirectory.path);
  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort: a test may still hold a file open on Windows.
    }
  });
}

String? _packageDirectory;

/// The absolute path of [path], relative to this package's directory.
///
/// For files checked in to this package, since [useTempWorkingDirectory]
/// resolves relative paths elsewhere.
String packagePath(String path) => p.join(_packageDirectory!, path);

/// The absolute path of this package's `test/fixtures` directory.
String get fixturesDirectory => packagePath(p.join('test', 'fixtures'));

final class _TempWorkingDirectoryOverrides extends IOOverrides {
  _TempWorkingDirectoryOverrides(this.workingDirectory);

  final String workingDirectory;

  // Against [Directory.current] rather than [workingDirectory], so a test that
  // overrides the current directory in a zone sees relative paths follow it.
  String _resolve(String path) =>
      p.isRelative(path) ? p.join(Directory.current.path, path) : path;

  @override
  Directory getCurrentDirectory() => super.createDirectory(workingDirectory);

  @override
  void setCurrentDirectory(String path) => throw UnsupportedError(
    'Tests must not change the process-wide working directory.',
  );

  @override
  Directory createDirectory(String path) =>
      super.createDirectory(_resolve(path));

  @override
  File createFile(String path) => super.createFile(_resolve(path));

  @override
  Link createLink(String path) => super.createLink(_resolve(path));

  @override
  Future<FileStat> stat(String path) => super.stat(_resolve(path));

  @override
  FileStat statSync(String path) => super.statSync(_resolve(path));

  @override
  Future<bool> fseIdentical(String path1, String path2) =>
      super.fseIdentical(_resolve(path1), _resolve(path2));

  @override
  bool fseIdenticalSync(String path1, String path2) =>
      super.fseIdenticalSync(_resolve(path1), _resolve(path2));

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) =>
      super.fseGetType(_resolve(path), followLinks);

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) =>
      super.fseGetTypeSync(_resolve(path), followLinks);

  @override
  Stream<FileSystemEvent> fsWatch(String path, int events, bool recursive) =>
      super.fsWatch(_resolve(path), events, recursive);
}

File createTempFile(String name) {
  return File(p.join(Directory.systemTemp.createTempSync().path, name))
    ..createSync();
}

/// Runs [body] with [Directory.systemTemp] redirected to [systemTemp], so a
/// test can check what [body] left behind there.
Future<void> runWithSystemTemp(
  Directory systemTemp,
  Future<void> Function() body,
) => IOOverrides.runZoned(body, getSystemTempDirectory: () => systemTemp);

/// A new, empty directory to stand in for [Directory.systemTemp].
Directory createSystemTemp() {
  final systemTemp = Directory.systemTemp.createTempSync();
  addTearDown(() => systemTemp.deleteSync(recursive: true));
  return systemTemp;
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

/// Runs [body], a command run in `--json` mode, and decodes the envelope it
/// wrote to stdout.
///
/// Fails the test unless exactly one line was written, since `--json` mode
/// emits a single envelope.
Future<({int exitCode, Map<String, dynamic> json})> captureJson(
  Future<int> Function() body,
) async {
  final captured = <String>[];
  final exitCode = await captureStdout(body, captured: captured);
  expect(captured, hasLength(1));
  return (
    exitCode: exitCode,
    json: jsonDecode(captured.single) as Map<String, dynamic>,
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
