import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(User, () {
    test('can be (de)serialized', () {
      const user = User(
        id: 1,
        email: 'test@shorebird.dev',
      );
      expect(
        User.fromJson(user.toJson()).toJson(),
        equals(user.toJson()),
      );
    });
  });
}
