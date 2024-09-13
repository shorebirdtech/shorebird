import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('AndroidArch', () {
    late EngineConfig engineConfig;

    setUp(() {
      engineConfig = MockEngineConfig();

      when(() => engineConfig.localEngine).thenReturn(null);
    });

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          engineConfigRef.overrideWith(() => engineConfig),
        },
      );
    }

    group('availableAndroidArchs', () {
      group('when no local engine is being used', () {
        setUp(() {
          when(() => engineConfig.localEngine).thenReturn(null);
        });

        test('returns all available architectures', () {
          expect(
            runWithOverrides(() => AndroidArch.availableAndroidArchs),
            equals(Arch.values),
          );
        });
      });

      group('when a local engine is being used', () {
        setUp(() {
          when(
            () => engineConfig.localEngine,
          ).thenReturn('android_release_arm64');
        });

        test('returns archs matching local engine arch', () async {
          expect(
            runWithOverrides(() => AndroidArch.availableAndroidArchs),
            equals([Arch.arm64]),
          );
        });

        test('throws exception when unknown engine architecture is used',
            () async {
          when(() => engineConfig.localEngine).thenReturn('unknown_arch');

          expect(
            () => runWithOverrides(() => AndroidArch.availableAndroidArchs),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'toString()',
                contains('Unknown local engine architecture for'),
              ),
            ),
          );
        });
      });
    });

    group('targetPlatformCliArg', () {
      test('returns correct arg', () {
        expect(Arch.arm32.targetPlatformCliArg, equals('android-arm'));
        expect(Arch.arm64.targetPlatformCliArg, equals('android-arm64'));
        expect(Arch.x86_64.targetPlatformCliArg, equals('android-x64'));
      });
    });

    group('androidBuildPath', () {
      test('returns correct path', () {
        expect(Arch.arm32.androidBuildPath, equals('armeabi-v7a'));
        expect(Arch.arm64.androidBuildPath, equals('arm64-v8a'));
        expect(Arch.x86_64.androidBuildPath, equals('x86_64'));
      });
    });

    group('androidEnginePath', () {
      test('returns correct path', () {
        expect(Arch.arm32.androidEnginePath, equals('android_release'));
        expect(Arch.arm64.androidEnginePath, equals('android_release_arm64'));
        expect(Arch.x86_64.androidEnginePath, equals('android_release_x64'));
      });
    });
  });
}
