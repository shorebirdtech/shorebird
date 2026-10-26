// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ZapScreenshotUpload', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = ZapScreenshotUpload(
        size: 0,
        contentType: ZapScreenshotContentType.imagePng,
      );
      final parsed = ZapScreenshotUpload.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ZapScreenshotUpload.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ZapScreenshotUpload.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
