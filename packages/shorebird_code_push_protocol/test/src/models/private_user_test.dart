import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PrivateUser, () {
    test('can be (de)serialized', () {
      const user = PrivateUser(
        id: 1,
        email: 'test@shorebird.dev',
        stripeCustomerId: 'test-customer-id',
        displayName: 'Test User',
        jwtIssuer: 'https://accounts.google.com',
        patchOverageLimit: 123,
      );
      expect(
        PrivateUser.fromJson(user.toJson()).toJson(),
        equals(user.toJson()),
      );
    });
  });
}
