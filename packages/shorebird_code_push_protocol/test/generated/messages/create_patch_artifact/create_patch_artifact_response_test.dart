// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreatePatchArtifactResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = CreatePatchArtifactResponse(
        id: 0,
        patchId: 0,
        arch: 'example',
        platform: ReleasePlatform.values.first,
        hash: 'example',
        size: 0,
        url: 'example',
      );
      final parsed = CreatePatchArtifactResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreatePatchArtifactResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreatePatchArtifactResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
