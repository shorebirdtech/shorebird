import 'package:money2/money2.dart';

/// The US dollar.
Currency get usd => Currency.create('USD', 2);

/// The Canadian dollar.
Currency get cad => Currency.create('CAD', 2);

/// Adds methods to [Money] to convert to and from a string with the currency
/// for transport.
extension MoneyTransport on Money {
  /// Converts a [Money] to a [String] with the currency code, using a space as
  /// a delimiter.
  /// Example: $1.00 -> "USD 100"
  String toTransportString() => '${currency.code} $minorUnits';

  /// Converts a string of the format "CURRENCY_CODE MINOR_UNITS" to a [Money].
  /// Example: "USD 100" -> $1.00
  static Money fromTransportString(String string) {
    final parts = string.split(' ');
    if (parts.length != 2) {
      throw FormatException('Invalid format for Money with Currency: $string');
    }

    final currencyCode = parts[0];
    final minorUnitsString = parts[1];
    final minorUnits = int.parse(minorUnitsString);
    return Money.fromInt(minorUnits, code: currencyCode);
  }
}
