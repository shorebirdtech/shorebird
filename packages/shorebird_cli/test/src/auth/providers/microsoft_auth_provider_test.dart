import 'package:shorebird_cli/src/auth/providers/providers.dart';
import 'package:test/test.dart';

void main() {
  group(MicrosoftAuthProvider, () {
    test('has valid endpoints', () {
      final provider = MicrosoftAuthProvider();
      expect(provider.authorizationEndpoint, isNotNull);
      expect(provider.tokenEndpoint, isNotNull);
    });
  });
}
