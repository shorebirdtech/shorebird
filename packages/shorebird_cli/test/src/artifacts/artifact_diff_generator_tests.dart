import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/artifacts/artifacts.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(ArtifactDiffGenerator, () {
    late ShorebirdProcessResult patchProcessResult;

    setUp(() {
      patchProcessResult = MockProcessResult();
    });

    group('', () {
      test('throws error when creating diff fails', () async {
        const error = 'oops something went wrong';
        when(() => patchProcessResult.exitCode).thenReturn(1);
        when(() => patchProcessResult.stderr).thenReturn(error);
        final tempDir = setUpTempDir();
        setUpTempArtifacts(tempDir);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        verify(
          () => progress.fail('Exception: Failed to create diff: $error'),
        ).called(1);
        expect(exitCode, ExitCode.software.code);
      });

      /// TODO
    });
  });
}
