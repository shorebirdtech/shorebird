import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Ditto, () {
    late ShorebirdProcess process;
    late Ditto ditto;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {processRef.overrideWith(() => process)});
    }

    setUp(() {
      process = MockShorebirdProcess();
      ditto = Ditto();
    });

    group('extract', () {
      const source = './source';
      const destination = './destination';

      group('when process exits with code 0', () {
        setUp(() {
          when(() => process.run('ditto', any())).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
            ),
          );
        });

        test('completes', () async {
          await expectLater(
            runWithOverrides(
              () => ditto.extract(source: source, destination: destination),
            ),
            completes,
          );
          verify(
            () => process.run('ditto', ['-x', '-k', source, destination]),
          ).called(1);
        });
      });

      group('when process exits with non-zero exit code', () {
        const error = 'oops something went wrong';
        setUp(() {
          when(() => process.run('ditto', any())).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: error,
            ),
          );
        });

        test('throws an exception', () async {
          await expectLater(
            runWithOverrides(
              () => ditto.extract(source: source, destination: destination),
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains(error),
              ),
            ),
          );
          verify(
            () => process.run('ditto', ['-x', '-k', source, destination]),
          ).called(1);
        });
      });
    });

    group('archive', () {
      const source = './source';
      const destination = './destination';

      group('when process exits with code 0', () {
        setUp(() {
          when(
            () => process.run('ditto', ['-c', '-k', source, destination]),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
            ),
          );
        });

        group('when keepParent is true', () {
          setUp(() {
            when(
              () => process.run('ditto', [
                '-c',
                '-k',
                '--keepParent',
                source,
                destination,
              ]),
            ).thenAnswer(
              (_) async => const ShorebirdProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
              ),
            );
          });

          test('completes', () async {
            await expectLater(
              runWithOverrides(
                () => ditto.archive(
                  source: source,
                  destination: destination,
                  keepParent: true,
                ),
              ),
              completes,
            );
            verify(
              () => process.run('ditto', [
                '-c',
                '-k',
                '--keepParent',
                source,
                destination,
              ]),
            ).called(1);
          });
        });

        test('completes', () async {
          await expectLater(
            runWithOverrides(
              () => ditto.archive(source: source, destination: destination),
            ),
            completes,
          );
          verify(
            () => process.run('ditto', ['-c', '-k', source, destination]),
          ).called(1);
        });
      });

      group('when process exits with non-zero exit code', () {
        const error = 'oops something went wrong';
        setUp(() {
          when(
            () => process.run('ditto', ['-c', '-k', source, destination]),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: error,
            ),
          );
        });

        test('throws an exception', () async {
          await expectLater(
            runWithOverrides(
              () => ditto.archive(source: source, destination: destination),
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains(error),
              ),
            ),
          );
          verify(
            () => process.run('ditto', ['-c', '-k', source, destination]),
          ).called(1);
        });
      });
    });
  });
}
