import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:test/test.dart';

void main() {
  group(ArtifactBuildException, () {
    group('can be instantiated', () {
      test('translates stdout and stderr to lists of strings', () {
        const message = 'message';
        const recommendation = 'recommendation';
        final exception = ArtifactBuildException(
          message,
          fixRecommendation: recommendation,
        );

        expect(exception.message, equals(message));
        expect(exception.fixRecommendation, equals(recommendation));
      });
    });
  });
}
