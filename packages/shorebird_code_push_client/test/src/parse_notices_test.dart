import 'package:shorebird_code_push_client/src/code_push_client.dart';
import 'package:test/test.dart';

void main() {
  group(parseNotices, () {
    test('reads a list of strings', () {
      expect(parseNotices('"a", "b, c"'), equals(['a', 'b, c']));
    });

    test('unescapes quotes and backslashes', () {
      expect(parseNotices(r'"say \"hi\" \\ bye"'), equals([r'say "hi" \ bye']));
    });

    test('tolerates whitespace and drops empty strings', () {
      expect(parseNotices(' "a" ,\t""  ,  "b" '), equals(['a', 'b']));
    });

    for (final value in [
      'plain text, not a list',
      '"unterminated',
      '"a" "b"',
      '"a",',
      r'"bad \escape"',
      r'"ends in backslash\',
    ]) {
      test('returns a malformed value whole: $value', () {
        expect(parseNotices(value), equals([value]));
      });
    }
  });
}
