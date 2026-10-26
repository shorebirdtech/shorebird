// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetZapPreviewsResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetZapPreviewsResponse(
        previews: <ZapPreviewSummary>[
          ZapPreviewSummary(
            id: 'example',
            name: 'example',
            build: 'example',
            updatedAt: DateTime.utc(2024),
            expiresAt: DateTime.utc(2024),
          ),
        ],
        channels: <ZapPreviewSummary>[
          ZapPreviewSummary(
            id: 'example',
            name: 'example',
            build: 'example',
            updatedAt: DateTime.utc(2024),
            expiresAt: DateTime.utc(2024),
          ),
        ],
      );
      final parsed = GetZapPreviewsResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetZapPreviewsResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetZapPreviewsResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
