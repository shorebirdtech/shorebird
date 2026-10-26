// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ZapPreviewSummary', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = ZapPreviewSummary(
        id: 'example',
        name: 'example',
        build: 'example',
        updatedAt: DateTime.utc(2024),
        expiresAt: DateTime.utc(2024),
      );
      final parsed = ZapPreviewSummary.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ZapPreviewSummary.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ZapPreviewSummary.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
