// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseAppSummary', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseAppSummary(
        id: 'example',
        displayName: 'example',
      );
      final parsed = EnterpriseAppSummary.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseAppSummary.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseAppSummary.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
