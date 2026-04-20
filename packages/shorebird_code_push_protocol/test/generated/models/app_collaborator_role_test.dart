// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AppCollaboratorRole', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = AppCollaboratorRole.values.first;
      final parsed = AppCollaboratorRole.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AppCollaboratorRole.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AppCollaboratorRole.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });
  });
}
