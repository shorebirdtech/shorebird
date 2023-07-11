import 'package:json_annotation/json_annotation.dart';
import 'package:money2/money2.dart';

/// The US dollar.
Currency get usd => Currency.create('USD', 2);

/// {@template money_converter}
/// Converts between [Money] and [int].
/// {@endtemplate}
// TODO(bryanoltman): change this to use String as the transport type the next
// time we make a breaking change to the API.
class MoneyConverter implements JsonConverter<Money, int> {
  /// {@macro money_converter}
  const MoneyConverter();

  @override
  Money fromJson(int cents) => Money.fromIntWithCurrency(cents, usd);

  @override
  int toJson(Money money) => money.minorUnits.toInt();
}
