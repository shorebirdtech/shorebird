import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'subscription.g.dart';

/// {@template subscription}
/// TODO
/// {@endtemplate}
@JsonSerializable()
class Subscription {
  /// {@macro subscription}
  Subscription({
    required this.cost,
    required this.paidThroughDate,
    required this.willRenew,
  });

  /// Creates a [Subscription] from a JSON object.
  factory Subscription.fromJson(Json json) => _$SubscriptionFromJson(json);

  /// Converts a [Subscription] to a JSON object.
  Json toJson() => _$SubscriptionToJson(this);

  /// Billing rate, in cents.
  final int cost;

  /// When the subscription will be renewed or expire.
  @TimestampConverter()
  final DateTime paidThroughDate;

  /// Whether this subscription will renew on [paidThroughDate].
  final bool willRenew;

  /// Whether this subscription is currently active.
  bool get isActive => paidThroughDate.isAfter(DateTime.now());
}
