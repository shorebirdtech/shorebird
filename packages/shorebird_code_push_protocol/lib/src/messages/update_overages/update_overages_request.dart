import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'update_overages_request.g.dart';

/// {@template update_overages_request}
/// The request body for PUT /api/v1/billing/overages
/// {@endtemplate}
@JsonSerializable()
class UpdateOveragesRequest {
  /// {@macro update_overages_request}
  const UpdateOveragesRequest({required this.patchInstallOverageLimit});

  /// Converts a Map<String, dynamic> to a [UpdateOveragesRequest].
  factory UpdateOveragesRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateOveragesRequestFromJson(json);

  /// Converts a [UpdateOveragesRequest] to a Map<String, dynamic>.
  Json toJson() => _$UpdateOveragesRequestToJson(this);

  /// The number of additional patch installs for the current billing period.
  /// `null` indicates that the user has unlimited patch installs.
  /// Defaults to 0.
  final int? patchInstallOverageLimit;
}
