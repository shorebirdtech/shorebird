import 'package:json_annotation/json_annotation.dart';
import 'package:money2/money2.dart';

/// The US dollar.
Currency get usd => Currency.create('USD', 2);

/// {@template money_converter}
/// Converts between [Money] and [String].
/// {@endtemplate}
class MoneyConverter implements JsonConverter<Money, String> {
  /// {@macro money_converter}
  const MoneyConverter();

  @override
  Money fromJson(String cents) => Money.parseWithCurrency(cents, usd);

  @override
  String toJson(Money money) => money.minorUnits.toString();
}
