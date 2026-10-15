// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PublicStat', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = PublicStat(
        value: 0,
        perSecond: 0,
        asOf: DateTime.utc(2024),
      );
      final parsed = PublicStat.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PublicStat.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PublicStat.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
