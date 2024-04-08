import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:test/test.dart';

void main() {
  test('IsNullOrEmpty', () async {
    expect(null.isNullOrEmpty, true);
    expect(''.isNullOrEmpty, true);
    expect('test'.isNullOrEmpty, false);
  });

   test('ToKebabCase', () async {
    expect('sentanceCase'.toKebabCase, 'sentance-case');
    expect('SentanceCase'.toKebabCase, 'sentance-case');
    expect('sentance_case'.toKebabCase, 'sentance-case');
    expect('sentance-case'.toKebabCase, 'sentance-case');
  });
}
