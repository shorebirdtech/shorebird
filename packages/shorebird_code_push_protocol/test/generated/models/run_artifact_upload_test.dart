// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RunArtifactUpload', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = RunArtifactUpload(
        id: 0,
        kind: RunArtifactKind.debugBundle,
        sharedBy: RunArtifactSharedBy.setting,
        uploadUrl: Uri.parse('https://example.com'),
      );
      final parsed = RunArtifactUpload.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RunArtifactUpload.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => RunArtifactUpload.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
