import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
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

    group('displayName', () {
      test('android', () {
        expect(ReleasePlatform.android.displayName, 'Android');
      });

      test('ios', () {
        expect(ReleasePlatform.ios.displayName, 'iOS');
      });

      test('linux', () {
        expect(ReleasePlatform.linux.displayName, 'Linux');
      });

      test('macos', () {
        expect(ReleasePlatform.macos.displayName, 'macOS');
      });

      test('windows', () {
        expect(ReleasePlatform.windows.displayName, 'Windows');
      });
    });
  });
}
