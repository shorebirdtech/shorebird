import 'package:shorebird_code_push_protocol/src/models/models.dart';
import 'package:test/test.dart';

void main() {
  group(ReleasePlatform, () {
    test('android supports flavors', () {
      expect(ReleasePlatform.android.supportsFlavors, isTrue);
    });

    test('ios supports flavors', () {
      expect(ReleasePlatform.ios.supportsFlavors, isTrue);
    });

    test('linux does not support flavors', () {
      expect(ReleasePlatform.linux.supportsFlavors, isFalse);
    });

    test('macos supports flavors', () {
      expect(ReleasePlatform.macos.supportsFlavors, isTrue);
    });

    test('windows does not support flavors', () {
      expect(ReleasePlatform.windows.supportsFlavors, isFalse);
    });
  });
}
