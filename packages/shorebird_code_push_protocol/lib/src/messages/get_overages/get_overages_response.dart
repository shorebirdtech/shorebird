import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_overages_response.g.dart';

/// {@template get_overages_response}
/// The response body for GET /api/v1/billing/overages
/// {@endtemplate}
@JsonSerializable()
class GetOveragesResponse {
  /// {@macro get_overages_response}
  const GetOveragesResponse({required this.patchInstallOverageLimit});

  /// Converts a Map<String, dynamic> to a [GetOveragesResponse].
  factory GetOveragesResponse.fromJson(Map<String, dynamic> json) =>
      _$GetOveragesResponseFromJson(json);

  /// Converts a [GetOveragesResponse] to a Map<String, dynamic>.
  Json toJson() => _$GetOveragesResponseToJson(this);

  /// The number of additional patch installs for the current billing period.
  /// `null` indicates that the user has unlimited patch installs.
  /// Defaults to 0.
  final int? patchInstallOverageLimit;
}
