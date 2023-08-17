import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('MoneyTransport', () {
    group('to String', () {
      test('converts a USD Money object to a String with the currency code',
          () {
        final money = Money.fromIntWithCurrency(100, usd);
        expect(money.toTransportString(), 'USD 100');
      });

      test('converts a CAD Money object to a String with the currency code',
          () {
        final money = Money.fromIntWithCurrency(987, cad);
        expect(money.toTransportString(), 'CAD 987');
      });
    });

    group('to Money', () {
      test('throws FormatException if string is not in the correct format', () {
        expect(
          () => MoneyTransport.fromTransportString('USD100'),
          throwsFormatException,
        );
      });

      test('converts a USD String to a Money object', () {
        final money = MoneyTransport.fromTransportString('USD 100');
        expect(money.currency, usd);
        expect(money.minorUnits, BigInt.from(100));
      });

      test('converts a CAD String to a Money object', () {
        final money = MoneyTransport.fromTransportString('CAD 999');
        expect(money.currency, cad);
        expect(money.minorUnits, BigInt.from(999));
      });
    });
  });
}
