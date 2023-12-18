import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:test/test.dart';

void main() {
  test('IsNullOrEmpty', () async {
    expect(null.isNullOrEmpty, true);
    expect(''.isNullOrEmpty, true);
    expect('test'.isNullOrEmpty, false);
  });
}
