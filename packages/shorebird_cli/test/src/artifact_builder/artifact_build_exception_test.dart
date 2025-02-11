import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

void main() {
  group(ArtifactBuildException, () {
    group('fromProcessResult', () {
      test('translates stdout and stderr to lists of strings', () {
        const buildProcessResult = ShorebirdProcessResult(
          exitCode: 1,
          stdout: 'stdout',
          stderr: 'stderr',
        );

        final exception = ArtifactBuildException.fromProcessResult(
          'message',
          buildProcessResult: buildProcessResult,
        );

        expect(exception.stdout, ['stdout']);
        expect(exception.stderr, ['stderr']);
      });
    });

    group('when no errors are recognized', () {
      test('returns a message with no fix recommendation or Flutter error', () {
        final exception = ArtifactBuildException(
          'message',
          stderr: ['some stderr output'],
          stdout: ['some stdout output'],
        );
        expect(exception.flutterError, isEmpty);
        expect(exception.fixRecommendation, isNull);
      });
    });

    group('when an error is recognized but no fix recommendation is found', () {
      test('has a Flutter error and no fix recommendation', () {
        final exception = ArtifactBuildException(
          'message',
          stderr: [
            'some stderr output',
            'FAILURE: Build failed with an exception.',
            '* Exception is:',
            'some stack trace',
            '* Try:',
            'some recommendation',
          ],
          stdout: ['some stdout output'],
        );
        expect(
          exception.flutterError,
          equals('FAILURE: Build failed with an exception.'),
        );
        expect(exception.fixRecommendation, isNull);
      });
    });

    group('when a known error is recognized and a fix recommendation is found',
        () {
      test('has a Flutter error and a fix recommendation', () {
        final exception = ArtifactBuildException(
          'message',
          stderr: [
            'some stderr output',
            'FAILURE: Build failed with an exception.',
            '* What went wrong:',
            "Execution failed for task ':app:signReleaseBundle'.",
            r'''> A failure occurred while executing com.android.build.gradle.internal.tasks.FinalizeBundleTask$BundleToolRunnable''',
            '> java.lang.NullPointerException (no error message)',
            '* Exception is:',
            'some stack trace',
            '* Try:',
            'some recommendation',
          ],
          stdout: ['some stdout output'],
        );
        expect(
          exception.flutterError,
          equals(r'''
FAILURE: Build failed with an exception.
* What went wrong:
Execution failed for task ':app:signReleaseBundle'.
> A failure occurred while executing com.android.build.gradle.internal.tasks.FinalizeBundleTask$BundleToolRunnable
> java.lang.NullPointerException (no error message)'''),
        );
        expect(
          exception.fixRecommendation,
          contains('This error is likely due to a missing keystore file'),
        );
      });
    });

    group('when a fix recommendation is provided', () {
      test('does not read output to find fix recommendation', () {
        final exception = ArtifactBuildException(
          'message',
          fixRecommendation: 'some recommendation',
          stderr: [
            'some stderr output',
            'FAILURE: Build failed with an exception.',
            '* Exception is:',
            'some stack trace',
            '* Try:',
            'some recommendation',
          ],
          stdout: ['some stdout output'],
        );
        expect(
          exception.flutterError,
          'FAILURE: Build failed with an exception.',
        );
        expect(exception.fixRecommendation, equals('some recommendation'));
      });
    });
  });
}
