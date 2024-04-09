import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:test/test.dart';

void main() {
  test('IsNullOrEmpty', () async {
    expect(null.isNullOrEmpty, true);
    expect(''.isNullOrEmpty, true);
    expect('test'.isNullOrEmpty, false);
  });

  test('ToKebabCase', () async {
    expect('sentenceCase'.toKebabCase, 'sentence-case');
    expect('SentenceCase'.toKebabCase, 'sentence-case');
    expect('sentence_case'.toKebabCase, 'sentence-case');
    expect('sentence-case'.toKebabCase, 'sentence-case');
    expect('sentence case'.toKebabCase, 'sentence-case');
  });
}
