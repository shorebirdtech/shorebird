// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchArtifact', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = PatchArtifact(
        id: 0,
        patchId: 0,
        arch: 'example',
        platform: ReleasePlatform.values.first,
        hash: 'example',
        size: 0,
        createdAt: DateTime.utc(2024),
      );
      final parsed = PatchArtifact.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchArtifact.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchArtifact.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
