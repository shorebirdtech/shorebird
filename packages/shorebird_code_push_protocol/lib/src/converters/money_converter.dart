import 'package:json_annotation/json_annotation.dart';
import 'package:money2/money2.dart';

/// The US dollar.
Currency get usd => Currency.create('USD', 2);

/// {@template money_converter}
/// Converts between [Money] and [BigInt].
/// {@endtemplate}
class MoneyConverter implements JsonConverter<Money, BigInt> {
  /// {@macro money_converter}
  const MoneyConverter();

  @override
  Money fromJson(BigInt cents) => Money.fromBigIntWithCurrency(cents, usd);

  @override
  BigInt toJson(Money money) => money.minorUnits;
}
