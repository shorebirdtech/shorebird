import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_process_tools/shorebird_process_tools.dart';

/// A reference to a [Dart] instance.
final dartRef = create(Dart.new);

/// The [Dart] instance available in the current zone.
Dart get dart => read(dartRef);

/// {@template dart_format_result}
/// The result of running `dart format`.
/// {@endtemplate}
class DartFormatResult {
  /// {@macro dart_format_result}
  DartFormatResult({
    required this.isFormattedCorrectly,
    required this.output,
  });

  /// Whether `dart format` changed any files.
  final bool isFormattedCorrectly;

  /// The stdout of the `dart format` command.
  final String output;
}

/// A wrapper around Dart-related functionality.
class Dart {
  /// Name of the dart executable.
  static const executable = 'dart';

  /// Runs `dart format` on the given [path].
  Future<DartFormatResult> format({
    required String path,
    bool setExitIfChanged = false,
  }) async {
    final formatResult = await process.run(
      executable,
      ['format', if (setExitIfChanged) '--set-exit-if-changed', path],
    );

    return DartFormatResult(
      isFormattedCorrectly: formatResult.exitCode == 0,
      output: formatResult.stdout as String,
    );
  }

  /// Runs `dart pub get` on the given [path].
  Future<void> pubGet({required String path}) async {
    final result = await process.run(executable, [
      'pub',
      'get',
    ], workingDirectory: path);

    if (result.exitCode != 0) {
      throw ProcessException(executable, [
        'pub',
        'get',
      ], result.stderr as String);
    }
  }
}
