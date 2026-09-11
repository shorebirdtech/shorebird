// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetReleaseArtifactsResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetReleaseArtifactsResponse(
        artifacts: <ReleaseArtifact>[
          ReleaseArtifact(
            id: 0,
            releaseId: 0,
            arch: 'example',
            platform: ReleasePlatform.values.first,
            hash: 'example',
            size: 0,
            url: 'example',
            canSideload: false,
          ),
        ],
      );
      final parsed = GetReleaseArtifactsResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetReleaseArtifactsResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetReleaseArtifactsResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
