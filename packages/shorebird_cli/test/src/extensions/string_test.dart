import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:test/test.dart';

void main() {
  test('IsNullOrEmpty', () async {
    expect(null.isNullOrEmpty, isTrue);
    expect(''.isNullOrEmpty, isTrue);
    expect('test'.isNullOrEmpty, isFalse);
  });

  test('IsUpperCase', () async {
    expect('TEST'.isUpperCase(), isTrue);
    expect('test'.isUpperCase(), isFalse);
    expect('Test'.isUpperCase(), isFalse);
  });
}
