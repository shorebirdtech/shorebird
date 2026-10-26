// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateZapPreviewBuildResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = CreateZapPreviewBuildResponse(
        build: 'example',
        uploadUrl: 'example',
        uploadMethod: ArtifactUploadMethod.multipart,
      );
      final parsed = CreateZapPreviewBuildResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateZapPreviewBuildResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreateZapPreviewBuildResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
