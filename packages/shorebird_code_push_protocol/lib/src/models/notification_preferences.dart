import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template notification_preferences}
/// How the user wants to be notified.
/// {@endtemplate}
@immutable
class NotificationPreferences {
  /// {@macro notification_preferences}
  const NotificationPreferences({
    required this.areEmailNotificationsEnabled,
  });

  /// Converts a `Map<String, dynamic>` to a [NotificationPreferences].
  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'NotificationPreferences',
      json,
      () => NotificationPreferences(
        areEmailNotificationsEnabled:
            json['are_email_notifications_enabled'] as bool,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static NotificationPreferences? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return NotificationPreferences.fromJson(json);
  }

  /// Whether the user receives email notifications. `true` for a
  /// user who has never set it.
  final bool areEmailNotificationsEnabled;

  /// Converts a [NotificationPreferences] to a `Map<String, dynamic>`.
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
    return other is NotificationPreferences &&
        areEmailNotificationsEnabled == other.areEmailNotificationsEnabled;
  }
}
