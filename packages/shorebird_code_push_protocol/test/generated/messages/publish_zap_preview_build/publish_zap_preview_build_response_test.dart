// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PublishZapPreviewBuildResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = PublishZapPreviewBuildResponse(
        preview: 'example',
        build: 'example',
        name: 'example',
        bytes: 0,
      );
      final parsed = PublishZapPreviewBuildResponse.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PublishZapPreviewBuildResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PublishZapPreviewBuildResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
