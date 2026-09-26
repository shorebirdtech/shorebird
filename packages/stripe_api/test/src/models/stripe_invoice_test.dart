import 'package:stripe_api/stripe_api.dart';
import 'package:test/test.dart';

void main() {
  group(StripeInvoice, () {
    test('deserializes from json', () {
      final invoice = StripeInvoice.fromJson({
        'id': 'in_123',
        'status': 'uncollectible',
      });

      expect(invoice.id, 'in_123');
      expect(invoice.status, StripeInvoiceStatus.uncollectible);
    });

    test('deserializes void as voided', () {
      final invoice = StripeInvoice.fromJson({
        'id': 'in_123',
        'status': 'void',
      });

      expect(invoice.status, StripeInvoiceStatus.voided);
    });

    test('deserializes a null status for an unknown one', () {
      final invoice = StripeInvoice.fromJson({
        'id': 'in_123',
        'status': 'something_new',
      });

      expect(invoice.status, isNull);
    });

    group('isPayable', () {
      test('is true for open and uncollectible invoices', () {
        for (final status in [
          StripeInvoiceStatus.open,
          StripeInvoiceStatus.uncollectible,
        ]) {
          expect(
            StripeInvoice(id: 'in_123', status: status).isPayable,
            isTrue,
            reason: '$status',
          );
        }
      });

      test('is false for every other status', () {
        for (final status in [
          StripeInvoiceStatus.draft,
          StripeInvoiceStatus.paid,
          StripeInvoiceStatus.voided,
          null,
        ]) {
          expect(
            StripeInvoice(id: 'in_123', status: status).isPayable,
            isFalse,
            reason: '$status',
          );
        }
      });
    });
  });
}
