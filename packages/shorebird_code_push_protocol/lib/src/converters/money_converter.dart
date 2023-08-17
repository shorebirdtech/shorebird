import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template money_converter}
/// Converts between [Money] and [int].
/// {@endtemplate}
class MoneyConverter implements JsonConverter<Money, String> {
  /// {@macro money_converter}
  const MoneyConverter();

  @override
  Money fromJson(String string) => MoneyTransport.fromTransportString(string);

  @override
  String toJson(Money money) => money.toTransportString();
}
