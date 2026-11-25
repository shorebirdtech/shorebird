// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateSymbolsRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = CreateSymbolsRequest(
        platform: ReleasePlatform.android,
        arch: 'example',
        format: SymbolsFormat.sbsymbols,
        compression: SymbolsCompression.gzip,
        size: 0,
      );
      final parsed = CreateSymbolsRequest.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateSymbolsRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreateSymbolsRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
