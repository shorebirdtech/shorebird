import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('User', () {
    test('can be (de)serialized', () {
      final user = User(
        id: 1,
        email: 'test@shorebird.dev',
        subscription: Subscription(
          cost: 100,
          paidThroughDate: DateTime.now(),
          willRenew: true,
        ),
      );
      expect(
        User.fromJson(user.toJson()).toJson(),
        equals(user.toJson()),
      );
    });
  });
}
