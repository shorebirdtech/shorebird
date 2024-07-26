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

      test('returns the path to app.dill (local engine)', () {
        const result = ShorebirdProcessResult(
          stdout: '''
          [        ] Will strip AOT snapshot manually after build and dSYM generation.
          [        ] executing: /Users/felix/Development/github.com/shorebirdtech/engine/src/out/ios_release/clang_x64/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=/Users/felix/Development/github.com/felangel/flutter_and_friends/.dart_tool/flutter_build/ae2d368b5940aefb0c55ff62186de056/arm64/snapshot_assembly.S /Users/felix/Development/github.com/felangel/flutter_and_friends/.dart_tool/flutter_build/ae2d368b5940aefb0c55ff62186de056/app.dill
          [+5435 ms] executing: sysctl hw.optional.arm64
''',
          stderr: '',
          exitCode: 0,
        );

        expect(
          result.findAppDill(),
          equals(
            '/Users/felix/Development/github.com/felangel/flutter_and_friends/.dart_tool/flutter_build/ae2d368b5940aefb0c55ff62186de056/app.dill',
          ),
        );
      });

      group('when path to app.dill contains a space', () {
        test('returns full path to app.dill, including the space(s)', () {
          const result = ShorebirdProcessResult(
            stdout: '''
            [   +3 ms] targetingApplePlatform = true
            [        ] extractAppleDebugSymbols = true
            [        ] Will strip AOT snapshot manually after build and dSYM generation.
            [        ] executing: /Users/bryanoltman/shorebirdtech/_shorebird/shorebird/bin/cache/flutter/9015e1b42a1ba41d97176e22b502b0e0e8ad28af/bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64 --deterministic --snapshot_kind=app-aot-assembly --assembly=/Users/bryanoltman/Documents/sandbox/folder with space/ios_patcher/.dart_tool/flutter_build/cd4f4aa272817365910648606e3e4164/arm64/snapshot_assembly.S /Users/bryanoltman/Documents/sandbox/folder with space/ios_patcher/.dart_tool/flutter_build/cd4f4aa272817365910648606e3e4164/app.dill
            [+3395 ms] executing: sysctl hw.optional.arm64
            [   +3 ms] Exit code 0 from: sysctl hw.optional.arm64
''',
            stderr: '',
            exitCode: 0,
          );

          expect(
            result.findAppDill(),
            equals(
              '/Users/bryanoltman/Documents/sandbox/folder with space/ios_patcher/.dart_tool/flutter_build/cd4f4aa272817365910648606e3e4164/app.dill',
            ),
          );
        });
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
