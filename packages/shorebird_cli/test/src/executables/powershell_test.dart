import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Powershell, () {
    late ShorebirdLogger logger;
    late ShorebirdProcessResult processResult;
    late ShorebirdProcess process;
    late Powershell powershell;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      logger = MockShorebirdLogger();
      processResult = MockShorebirdProcessResult();
      process = MockShorebirdProcess();

      when(
        () => process.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => processResult);

      powershell = runWithOverrides(Powershell.new);
    });

    group('getProductVersion', () {
      group('when exit code is not success', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(1);
        });

        test('throws an exception', () async {
          await expectLater(
            runWithOverrides(() => powershell.getProductVersion(File(''))),
            throwsA(isA<Exception>()),
          );
        });
      });

      group('when exit code is success', () {
        group('when version code includes a build number', () {
          setUp(() {
            when(() => processResult.exitCode).thenReturn(0);
            when(() => processResult.stdout).thenReturn('1.0.0+1');
          });

          test('returns unaltered version string', () async {
            final version = await runWithOverrides(
              () => powershell.getProductVersion(File('')),
            );
            expect(version, '1.0.0+1');
          });
        });

        group('when path contains a space', () {
          setUp(() {
            when(() => processResult.exitCode).thenReturn(0);
            when(() => processResult.stdout).thenReturn('1.0.0+1');
          });

          test('executes correct command', () async {
            final directory = Directory.systemTemp.createTempSync(
              'directory with spaces',
            );
            final file = File('${directory.path}/file.exe');
            await runWithOverrides(() => powershell.getProductVersion(file));
            verify(
              () => process.run('powershell.exe', [
                '-Command',
                "(Get-Item -Path '${file.path}').VersionInfo.ProductVersion",
              ]),
            ).called(1);
          });
        });

        group('when version code does not include a build number', () {
          setUp(() {
            when(() => processResult.exitCode).thenReturn(0);
            when(() => processResult.stdout).thenReturn('1.0.0');
          });

          test(
            'returns the version string without a build number',
            () async {
              final version = await runWithOverrides(
                () => powershell.getProductVersion(File('')),
              );
              expect(version, '1.0.0');
            },
          );
        });
      });
    });
  });
}
