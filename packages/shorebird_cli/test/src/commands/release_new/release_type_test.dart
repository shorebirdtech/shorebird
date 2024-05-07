import 'package:shorebird_cli/src/commands/release_new/release_type.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

void main() {
  group(ReleaseType, () {
    test('cliName', () {
      expect(ReleaseType.android.cliName, 'android');
      expect(ReleaseType.ios.cliName, 'ios');
      expect(ReleaseType.iosFramework.cliName, 'ios-framework');
      expect(ReleaseType.aar.cliName, 'aar');
    });

    test('releasePlatform', () {
      expect(ReleaseType.android.releasePlatform, ReleasePlatform.android);
      expect(ReleaseType.ios.releasePlatform, ReleasePlatform.ios);
      expect(ReleaseType.iosFramework.releasePlatform, ReleasePlatform.ios);
      expect(ReleaseType.aar.releasePlatform, ReleasePlatform.android);
    });
  });
}
