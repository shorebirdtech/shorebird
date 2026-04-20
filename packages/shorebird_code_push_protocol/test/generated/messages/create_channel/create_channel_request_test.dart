// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateChannelRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = CreateChannelRequest(channel: 'example');
      final parsed = CreateChannelRequest.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateChannelRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreateChannelRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
