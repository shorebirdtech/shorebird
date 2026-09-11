import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shorebird_ci/src/flutter_version_resolver.dart';

/// Resolves the Flutter version from pubspec environment constraints.
///
/// This command exists because `subosito/flutter-action` only accepts exact
/// version strings — it cannot resolve constraints like `>=3.19.0 <4.0.0`
/// from the pubspec `environment.flutter` field.
///
/// Ideally this would be unnecessary: the Flutter ecosystem should provide a
/// standard way to resolve "which Flutter version satisfies my pubspec?" and
/// actions like `subosito/flutter-action` should consume it natively. If that
/// happens, this command should be deprecated in favor of the upstream
/// solution.
class FlutterVersionCommand extends Command<int> {
  /// Creates a [FlutterVersionCommand].
  FlutterVersionCommand() {
    argParser.addOption(
      'pubspec',
      help: 'Path to the package directory containing pubspec.yaml.',
      defaultsTo: '.',
    );
  }

  @override
  String get name => 'flutter_version';

  @override
  String get description => 'Resolve Flutter version from pubspec';

  @override
  Future<int> run() async {
    final packagePath = argResults!['pubspec'] as String;
    final version = resolveFlutterVersionOrStable(packagePath: packagePath);
    stdout.writeln(version);
    if (version == 'stable') {
      stderr.writeln(
        'No exact Flutter version found in pubspec.yaml, '
        'using stable.',
      );
    }
    return 0;
  }
}
