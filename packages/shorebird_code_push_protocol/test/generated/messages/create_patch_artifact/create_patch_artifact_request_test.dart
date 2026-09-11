// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreatePatchArtifactRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = CreatePatchArtifactRequest(
        arch: 'example',
        platform: ReleasePlatform.values.first,
        hash: 'example',
        size: 0,
      );
      final parsed = CreatePatchArtifactRequest.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreatePatchArtifactRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreatePatchArtifactRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
