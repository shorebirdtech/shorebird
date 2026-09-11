// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PendingRelease', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = PendingRelease(
        id: 0,
        version: 'example',
        createdAt: DateTime.utc(2024),
      );
      final parsed = PendingRelease.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PendingRelease.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PendingRelease.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
