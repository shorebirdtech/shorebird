import 'package:money2/money2.dart';

/// Defines currencies used by Shorebird.
extension ShorebirdCurrency on Currency {
  /// The US dollar.
  static Currency get usd => Currency.create('USD', 2);
}
