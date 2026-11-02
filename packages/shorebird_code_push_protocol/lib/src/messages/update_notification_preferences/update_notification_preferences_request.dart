import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template update_notification_preferences_request}
/// The request body for PATCH /users/me/notification_preferences. A
/// field left out, or sent as `null`, is left unchanged.
/// {@endtemplate}
@immutable
class UpdateNotificationPreferencesRequest {
  /// {@macro update_notification_preferences_request}
  const UpdateNotificationPreferencesRequest({
    this.areEmailNotificationsEnabled,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [UpdateNotificationPreferencesRequest].
  factory UpdateNotificationPreferencesRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'UpdateNotificationPreferencesRequest',
      json,
      () => UpdateNotificationPreferencesRequest(
        areEmailNotificationsEnabled:
            json['are_email_notifications_enabled'] as bool?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdateNotificationPreferencesRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return UpdateNotificationPreferencesRequest.fromJson(json);
  }

  /// Whether the user should receive email notifications.
  final bool? areEmailNotificationsEnabled;

  /// Converts a [UpdateNotificationPreferencesRequest]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'are_email_notifications_enabled': areEmailNotificationsEnabled,
    };
  }

  @override
  int get hashCode => areEmailNotificationsEnabled.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateNotificationPreferencesRequest &&
        areEmailNotificationsEnabled == other.areEmailNotificationsEnabled;
  }
}
