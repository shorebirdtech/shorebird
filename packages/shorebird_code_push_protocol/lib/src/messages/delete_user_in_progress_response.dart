import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template delete_user_in_progress_response}
/// An account delete that stopped partway, before its request timeout.
/// Repeat the request to continue.
/// {@endtemplate}
@immutable
class DeleteUserInProgressResponse {
  /// {@macro delete_user_in_progress_response}
  const DeleteUserInProgressResponse({
    required this.remainingAppCount,
  });

  /// Converts a `Map<String, dynamic>` to a [DeleteUserInProgressResponse].
  factory DeleteUserInProgressResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'DeleteUserInProgressResponse',
      json,
      () => DeleteUserInProgressResponse(
        remainingAppCount: json['remaining_app_count'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static DeleteUserInProgressResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return DeleteUserInProgressResponse.fromJson(json);
  }

  /// The apps still to delete when the request stopped.
  final int remainingAppCount;

  /// Converts a [DeleteUserInProgressResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'remaining_app_count': remainingAppCount,
    };
  }

  @override
  int get hashCode => remainingAppCount.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeleteUserInProgressResponse &&
        remainingAppCount == other.remainingAppCount;
  }
}
