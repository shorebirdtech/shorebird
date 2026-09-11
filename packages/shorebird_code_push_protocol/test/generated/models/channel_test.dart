// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Channel', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = Channel(id: 0, appId: 'example', name: 'example');
      final parsed = Channel.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(Channel.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => Channel.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
