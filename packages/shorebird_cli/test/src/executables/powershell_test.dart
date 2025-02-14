import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Powershell, () {
    late ShorebirdProcessResult processResult;
    late ShorebirdProcess process;
    late Powershell powershell;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {processRef.overrideWith(() => process)},
      );
    }

    setUp(() {
      processResult = MockShorebirdProcessResult();
      process = MockShorebirdProcess();

      when(
        () => process.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => processResult);

      powershell = runWithOverrides(Powershell.new);
    });

    group('getExeVersionString', () {
      group('when exit code is not success', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(1);
        });

        test('throws an exception', () async {
          await expectLater(
            runWithOverrides(() => powershell.getExeVersionString(File(''))),
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
              () => powershell.getExeVersionString(File('')),
            );
            expect(version, '1.0.0+1');
          });
        });

        group('when version code does not include a build number', () {
          setUp(() {
            when(() => processResult.exitCode).thenReturn(0);
            when(() => processResult.stdout).thenReturn('1.0.0');
          });

          test(
            'returns the version string with build number 0 added',
            () async {
              final version = await runWithOverrides(
                () => powershell.getExeVersionString(File('')),
              );
              expect(version, '1.0.0+0');
            },
          );
        });
      });
    });
  });
}
