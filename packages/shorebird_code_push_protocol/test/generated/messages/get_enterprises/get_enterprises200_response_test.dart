// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetEnterprises200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetEnterprises200Response(
        totalCount: 0,
        enterprises: <EnterpriseMembership>[
          EnterpriseMembership(
            id: 0,
            name: 'example',
            role: EnterpriseRole.owner,
          ),
        ],
      );
      final parsed = GetEnterprises200Response.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetEnterprises200Response.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetEnterprises200Response.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
