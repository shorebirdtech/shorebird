// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateReleaseArtifactResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = CreateReleaseArtifactResponse(
        id: 0,
        releaseId: 0,
        arch: 'example',
        platform: ReleasePlatform.values.first,
        hash: 'example',
        size: 0,
        url: 'example',
      );
      final parsed = CreateReleaseArtifactResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateReleaseArtifactResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreateReleaseArtifactResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
