import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ErrorResponse, () {
    test('can be (de)serialized', () {
      const response = ErrorResponse(
        code: 'code',
        message: 'message',
        details: 'details',
      );
      expect(
        ErrorResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
