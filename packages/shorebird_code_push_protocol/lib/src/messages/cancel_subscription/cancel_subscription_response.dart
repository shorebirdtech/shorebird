import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'cancel_subscription_response.g.dart';

/// {@template cancel_subscription_response}
/// The request body for DELETE /api/v1/subscriptions.
/// {@endtemplate}
@JsonSerializable()
class CancelSubscriptionResponse {
  /// {@macro cancel_subscription_response}
  CancelSubscriptionResponse({required this.expirationDate});

  /// Converts a JSON object to a [CancelSubscriptionResponse].
  factory CancelSubscriptionResponse.fromJson(Json json) =>
      _$CancelSubscriptionResponseFromJson(json);

  /// Converts a [CancelSubscriptionResponse] to a JSON object.
  Json toJson() => _$CancelSubscriptionResponseToJson(this);

  /// When this subscription will not longer be active.
  @TimestampConverter()
  final DateTime expirationDate;
}
