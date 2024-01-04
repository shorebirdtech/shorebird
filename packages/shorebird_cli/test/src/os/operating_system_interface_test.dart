import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(OperatingSystemInterface, () {
    late Platform platform;
    late ShorebirdProcess process;
    late ShorebirdProcessResult processResult;
    late OperatingSystemInterface osInterface;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      platform = MockPlatform();
      process = MockShorebirdProcess();
      processResult = MockProcessResult();

      when(() => platform.isLinux).thenReturn(false);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => platform.isWindows).thenReturn(false);

      when(() => process.runSync(any(), any())).thenReturn(processResult);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
    });

    group('init', () {
      test('throws UnsupportedError when operating system is not supported',
          () {
        expect(
          () => runWithOverrides(OperatingSystemInterface.new),
          throwsUnsupportedError,
        );
      });
    });

    group('on macOS/Linux', () {
      setUp(() {
        when(() => platform.isMacOS).thenReturn(true);

        osInterface = runWithOverrides(OperatingSystemInterface.new);
      });

      group('which()', () {
        group('when no executable is found on PATH', () {
          setUp(() {
            when(() => processResult.exitCode).thenReturn(1);
          });

          test('returns null', () {
            expect(
              runWithOverrides(() => osInterface.which('shorebird')),
              isNull,
            );
          });
        });

        group('when executable is found on PATH', () {
          const shorebirdPath = '/path/to/shorebird';
          setUp(() {
            when(() => processResult.stdout).thenReturn(shorebirdPath);
          });

          test('returns path to executable', () {
            expect(
              runWithOverrides(() => osInterface.which('shorebird')),
              shorebirdPath,
            );
          });
        });

        group('when executable contains leading and trailing newlines', () {
          const shorebirdPath = '''


/path/to/shorebird

''';
          setUp(() {
            when(() => processResult.stdout).thenReturn(shorebirdPath);
          });

          test('returns trimmed path to binary', () {
            expect(
              runWithOverrides(() => osInterface.which('shorebird')),
              equals('/path/to/shorebird'),
            );
          });
        });
      });
    });

    group('on Windows', () {
      setUp(() {
        when(() => platform.isWindows).thenReturn(true);
        osInterface = runWithOverrides(OperatingSystemInterface.new);
      });

      group('which()', () {
        group('when no executable is found on PATH', () {
          setUp(() {
            when(() => processResult.exitCode).thenReturn(1);
          });

          test('returns null', () {
            expect(
              runWithOverrides(() => osInterface.which('shorebird')),
              isNull,
            );
          });
        });

        group('when executable is found on PATH', () {
          const shorebirdPath = r'C:\path\to\shorebird';
          setUp(() {
            when(() => processResult.stdout).thenReturn(shorebirdPath);
          });

          test('returns path to executable', () {
            expect(
              runWithOverrides(() => osInterface.which('shorebird')),
              shorebirdPath,
            );
          });
        });

        group('when multiple executables are found on PATH', () {
          const shorebirdPath = r'C:\path\to\shorebird';
          const shorebirdPaths = r'''
C:\path\to\shorebird
C:\path\to\shorebird1
C:\path\to\shorebird2
C:\path\to\shorebird3''';

          setUp(() {
            when(() => processResult.stdout).thenReturn(shorebirdPaths);
          });

          test('returns first path to executable', () {
            expect(
              runWithOverrides(() => osInterface.which('shorebird')),
              shorebirdPath,
            );
          });
        });
      });
    });
  });
}
