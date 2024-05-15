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
          when(() => engineConfig.localEngine)
              .thenReturn('android_release_arm64');
        });

        test('returns archs matching local engine arch', () async {
          expect(
            runWithOverrides(() => AndroidArch.availableAndroidArchs),
            equals([Arch.arm64]),
          );
        });
      });
    });
  });
}
