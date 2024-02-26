import 'package:shorebird_cli/src/auth/endpoints/endpoints.dart';
import 'package:test/test.dart';

void main() {
  group(MicrosoftAuthEndpoints, () {
    test('has valid endpoints', () {
      final provider = MicrosoftAuthEndpoints();
      expect(provider.authorizationEndpoint, isNotNull);
      expect(provider.tokenEndpoint, isNotNull);
    });
  });
}
