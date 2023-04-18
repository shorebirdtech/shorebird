import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePaymentLinkResponse, () {
    test('can be (de)serialized', () {
      final response = CreatePaymentLinkResponse(
        paymentLink: Uri.parse('https://buy.stripe.com/asdfasdf'),
      );
      expect(
        CreatePaymentLinkResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
