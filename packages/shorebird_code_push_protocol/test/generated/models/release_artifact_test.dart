// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseArtifact', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = ReleaseArtifact(
        id: 0,
        releaseId: 0,
        arch: 'example',
        platform: ReleasePlatform.values.first,
        hash: 'example',
        size: 0,
        url: 'example',
        canSideload: false,
      );
      final parsed = ReleaseArtifact.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ReleaseArtifact.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ReleaseArtifact.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
