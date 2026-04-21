// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('App', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = App(id: 'example', displayName: 'example');
      final parsed = App.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(App.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => App.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
