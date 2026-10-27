import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/notification_preferences.dart';

/// {@template get_notification_preferences_response}
/// The response body for GET /users/me/notification_preferences.
/// {@endtemplate}
@immutable
class GetNotificationPreferencesResponse {
  /// {@macro get_notification_preferences_response}
  const GetNotificationPreferencesResponse({
    required this.preferences,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [GetNotificationPreferencesResponse].
  factory GetNotificationPreferencesResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'GetNotificationPreferencesResponse',
      json,
      () => GetNotificationPreferencesResponse(
        preferences: NotificationPreferences.fromJson(
          json['preferences'] as Map<String, dynamic>,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetNotificationPreferencesResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetNotificationPreferencesResponse.fromJson(json);
  }

  /// How the user wants to be notified.
  final NotificationPreferences preferences;

  /// Converts a [GetNotificationPreferencesResponse]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'preferences': preferences.toJson(),
    };
  }

  @override
  int get hashCode => preferences.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetNotificationPreferencesResponse &&
        preferences == other.preferences;
  }
}
