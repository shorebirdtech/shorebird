import 'package:shorebird_cli/src/extensions/shorebird_process_result.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

void main() {
  group('FindAppDill', () {
    group('when gen_snapshot is invoked with app.dill', () {
      test('returns the path to app.dill', () {
        const result = ShorebirdProcessResult(
          stdout: '''
           [        ] Will strip AOT snapshot manually after build and dSYM generation.
           [        ] executing: /Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/985ec84cb99d3c60341e2c78be9826e0a88cc697/bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=/Users/bryanoltman/Documents/sandbox/ios_signing/.dart_tool/flutter_build/804399dd5f8e05d7b9ec7e0bb4ceb22c/arm64/snapshot_assembly.S /Users/bryanoltman/Documents/sandbox/ios_signing/.dart_tool/flutter_build/804399dd5f8e05d7b9ec7e0bb4ceb22c/app.dill
           [+3688 ms] executing: sysctl hw.optional.arm64
''',
          stderr: '',
          exitCode: 0,
        );

        expect(
          result.findAppDill(),
          equals(
            '/Users/bryanoltman/Documents/sandbox/ios_signing/.dart_tool/flutter_build/804399dd5f8e05d7b9ec7e0bb4ceb22c/app.dill',
          ),
        );
      });
    });

    group('when gen_snapshot is not invoked with app.dill', () {
      test('returns null', () {
        const result = ShorebirdProcessResult(
          stdout: 'executing: .../gen_snapshot_arm64 .../snapshot_assembly.S',
          stderr: '',
          exitCode: 0,
        );

        expect(result.findAppDill(), isNull);
      });
    });
  });
}
