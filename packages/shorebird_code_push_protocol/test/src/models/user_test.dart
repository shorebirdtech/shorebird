import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(User, () {
    test('can be (de)serialized', () {
      const user = User(
        id: 1,
        email: 'test@shorebird.dev',
        stripeCustomerId: 'test-customer-id',
        displayName: 'Test User',
      );
      expect(
        User.fromJson(user.toJson()).toJson(),
        equals(user.toJson()),
      );
    });

    test(
        'supports creating a user without a stripeCustomerId '
        'for backward compatibility', () {
      const user = User(
        id: 1,
        email: 'test@shorebird.dev',
        displayName: 'Test User',
      );
      expect(
        User.fromJson({
          'id': 1,
          'email': 'test@shorebird.dev',
          'display_name': 'Test User',
        }).toJson(),
        equals(user.toJson()),
      );
    });
  });
}
