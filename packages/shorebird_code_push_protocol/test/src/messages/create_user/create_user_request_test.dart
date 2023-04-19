import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateUserRequest, () {
    test('can be (de)serialized', () {
      const request = CreateUserRequest(name: 'Joe Tester');
      expect(
        CreateUserRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
