// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ZapPreview', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = ZapPreview(
        formatVersion: 0,
        preview: 'example',
        channel: 'example',
        build: 'example',
        buildNumber: 0,
        name: 'example',
        payloadUrl: 'example',
        payload: 'example',
        payloadFormat: 'example',
        payloadSize: 0,
        expiresAt: DateTime.utc(2024),
      );
      final parsed = ZapPreview.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ZapPreview.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ZapPreview.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
