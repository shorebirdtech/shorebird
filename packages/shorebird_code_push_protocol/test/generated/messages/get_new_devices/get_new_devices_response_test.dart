// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetNewDevicesResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetNewDevicesResponse(
        current: 0,
        previous: 0,
        windowDays: 0,
        asOf: DateTime.utc(2024),
      );
      final parsed = GetNewDevicesResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetNewDevicesResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetNewDevicesResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
