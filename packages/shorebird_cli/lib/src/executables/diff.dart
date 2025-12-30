import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// The color mode for the `diff` command.
enum DiffColorMode {
  /// Never color the diff.
  never,

  /// Always color the diff.
  always,

  /// Color the diff automatically based on the output device.
  auto,
}

/// A reference to a [Diff] instance.
final diffRef = create(Diff.new);

/// The [Diff] instance available in the current zone.
Diff get diff => read(diffRef);

/// A wrapper around the `diff` command.
class Diff {
  /// The name of the `diff` executable.
  static const executable = 'diff';

  /// Runs the `diff` command and returns the result.
  Future<ShorebirdProcessResult> run(
    String fileAPath,
    String fileBPath, {
    required bool unified,
    required DiffColorMode colorMode,
  }) async {
    return process.run(executable, [
      if (unified) '--unified',
      '--color=${colorMode.name}',
      fileAPath,
      fileBPath,
    ]);
  }
}
