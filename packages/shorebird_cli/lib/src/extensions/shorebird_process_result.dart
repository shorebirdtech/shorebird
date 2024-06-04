import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

extension FindAppDill on ShorebirdProcessResult {
  /// Finds a line in stdout that invokes gen_snapshot with app.dill as an
  /// argument. The path to the app.dill file is the last argument in the line.
  ///
  /// Example matching line from `flutter build ipa`:
  ///   [        ] executing: /Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/985ec84cb99d3c60341e2c78be9826e0a88cc697/bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=/Users/bryanoltman/Documents/sandbox/ios_signing/.dart_tool/flutter_build/804399dd5f8e05d7b9ec7e0bb4ceb22c/arm64/snapshot_assembly.S /Users/bryanoltman/Documents/sandbox/ios_signing/.dart_tool/flutter_build/804399dd5f8e05d7b9ec7e0bb4ceb22c/app.dill
  ///
  /// Returns null if no matching line is found.
  String? findAppDill() {
    final appDillLine = stdout.toString().split('\n').firstWhereOrNull(
          (l) =>
              l.contains('ios-release/gen_snapshot') && l.endsWith('app.dill'),
        );
    return appDillLine?.split(' ').last;
  }
}
