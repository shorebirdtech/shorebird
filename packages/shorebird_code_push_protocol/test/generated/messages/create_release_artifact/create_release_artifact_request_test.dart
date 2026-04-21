// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateReleaseArtifactRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = CreateReleaseArtifactRequest(
        arch: 'example',
        platform: ReleasePlatform.values.first,
        hash: 'example',
        filename: 'example',
        size: 0,
      );
      final parsed = CreateReleaseArtifactRequest.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateReleaseArtifactRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreateReleaseArtifactRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
