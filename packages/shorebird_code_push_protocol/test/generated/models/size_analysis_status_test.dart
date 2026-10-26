// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SizeAnalysisStatus', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = SizeAnalysisStatus.succeeded;
      final parsed = SizeAnalysisStatus.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(SizeAnalysisStatus.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => SizeAnalysisStatus.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in SizeAnalysisStatus.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in SizeAnalysisStatus.values) {
        expect(SizeAnalysisStatus.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
