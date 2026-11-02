import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template transfer_organization_app_request}
/// The request body for POST /organizations/{organizationId}/apps.
/// {@endtemplate}
@immutable
class TransferOrganizationAppRequest {
  /// {@macro transfer_organization_app_request}
  const TransferOrganizationAppRequest({
    required this.appId,
  });

  /// Converts a `Map<String, dynamic>` to a [TransferOrganizationAppRequest].
  factory TransferOrganizationAppRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'TransferOrganizationAppRequest',
      json,
      () => TransferOrganizationAppRequest(
        appId: json['app_id'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static TransferOrganizationAppRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return TransferOrganizationAppRequest.fromJson(json);
  }

  /// The ID of the app to move into the organization.
  final String appId;

  /// Converts a [TransferOrganizationAppRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'app_id': appId,
    };
  }

  @override
  int get hashCode => appId.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransferOrganizationAppRequest && appId == other.appId;
  }
}
