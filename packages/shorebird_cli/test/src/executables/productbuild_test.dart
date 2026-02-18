import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(ProductBuild, () {
    late ShorebirdProcess process;
    late ProductBuild productBuildExecutable;

    setUp(() {
      process = MockShorebirdProcess();
      productBuildExecutable = const ProductBuild();
    });

    group('build', () {
      test(
        'builds package from existing package with required arguments',
        () async {
          when(
            () => process.run(
              any(),
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer(
            (_) async => ShorebirdProcessResult(
              exitCode: ExitCode.success.code,
              stdout: '',
              stderr: '',
            ),
          );

          await runScoped(
            () => productBuildExecutable.build(
              packagePath: '/path/to/input.pkg',
              outputPath: '/path/to/output.pkg',
            ),
            values: {
              processRef.overrideWith(() => process),
            },
          );

          verify(
            () => process.run(
              'productbuild',
              [
                '--package',
                '/path/to/input.pkg',
                '/path/to/output.pkg',
              ],
              runInShell: true,
            ),
          ).called(1);
        },
      );

      test('builds package with signing identity', () async {
        when(
          () => process.run(
            any(),
            any(),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer(
          (_) async => ShorebirdProcessResult(
            exitCode: ExitCode.success.code,
            stdout: '',
            stderr: '',
          ),
        );

        await runScoped(
          () => productBuildExecutable.build(
            packagePath: '/path/to/input.pkg',
            outputPath: '/path/to/output.pkg',
            sign: 'Developer ID Installer: Test Company (XXXXXXXXX)',
          ),
          values: {
            processRef.overrideWith(() => process),
          },
        );

        verify(
          () => process.run(
            'productbuild',
            [
              '--package',
              '/path/to/input.pkg',
              '--sign',
              'Developer ID Installer: Test Company (XXXXXXXXX)',
              '/path/to/output.pkg',
            ],
            runInShell: true,
          ),
        ).called(1);
      });
    });

    group('buildFromComponent', () {
      test('builds package from component with required arguments', () async {
        when(
          () => process.run(
            any(),
            any(),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer(
          (_) async => ShorebirdProcessResult(
            exitCode: ExitCode.success.code,
            stdout: '',
            stderr: '',
          ),
        );

        await runScoped(
          () => productBuildExecutable.buildFromComponent(
            componentPath: '/path/to/app.app',
            installLocation: '/Applications',
            outputPath: '/path/to/output.pkg',
          ),
          values: {
            processRef.overrideWith(() => process),
          },
        );

        verify(
          () => process.run(
            'productbuild',
            [
              '--component',
              '/path/to/app.app',
              '/Applications',
              '/path/to/output.pkg',
            ],
            runInShell: true,
          ),
        ).called(1);
      });

      test('builds package from component with signing identity', () async {
        when(
          () => process.run(
            any(),
            any(),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer(
          (_) async => ShorebirdProcessResult(
            exitCode: ExitCode.success.code,
            stdout: '',
            stderr: '',
          ),
        );

        await runScoped(
          () => productBuildExecutable.buildFromComponent(
            componentPath: '/path/to/app.app',
            installLocation: '/Applications',
            outputPath: '/path/to/output.pkg',
            sign: 'Developer ID Installer: Test Company (XXXXXXXXX)',
          ),
          values: {
            processRef.overrideWith(() => process),
          },
        );

        verify(
          () => process.run(
            'productbuild',
            [
              '--component',
              '/path/to/app.app',
              '/Applications',
              '--sign',
              'Developer ID Installer: Test Company (XXXXXXXXX)',
              '/path/to/output.pkg',
            ],
            runInShell: true,
          ),
        ).called(1);
      });
    });
  });
}
