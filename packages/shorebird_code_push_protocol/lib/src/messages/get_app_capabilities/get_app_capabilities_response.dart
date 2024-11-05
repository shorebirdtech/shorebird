import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_app_capabilities_response.g.dart';

/// {@template get_app_capabilities_response}
/// The capabilities of the requesting user for the specified app.
///
/// Response body for api/v1/apps/:appId/capabilities.
/// {@endtemplate}
@JsonSerializable()
class GetAppCapabilitiesResponse {
  /// {@macro get_app_capabilities_response}
  GetAppCapabilitiesResponse({required this.capabilities});

  /// Deserializes the [GetAppCapabilitiesResponse] from a JSON map.
  factory GetAppCapabilitiesResponse.fromJson(Map<String, dynamic> json) =>
      _$GetAppCapabilitiesResponseFromJson(json);

  /// Converts this [GetAppCapabilitiesResponse] to a JSON map.
  Map<String, dynamic> toJson() => _$GetAppCapabilitiesResponseToJson(this);

  /// The list of capabilities the user has for the app. There are the things
  /// that the requesting user can do to or in relation to the app. These are
  /// determined by the user's role in the organization that owns the app, the
  /// user's app collaborator status, and the plan associated with the app's
  /// organization.
  final List<AppCapability> capabilities;
}
