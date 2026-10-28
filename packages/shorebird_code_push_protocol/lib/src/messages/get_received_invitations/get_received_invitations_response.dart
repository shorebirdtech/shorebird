import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/received_invitation.dart';

/// {@template get_received_invitations_response}
/// The response body for GET /invitations.
/// {@endtemplate}
@immutable
class GetReceivedInvitationsResponse {
  /// {@macro get_received_invitations_response}
  const GetReceivedInvitationsResponse({
    required this.invitations,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetReceivedInvitationsResponse].
  factory GetReceivedInvitationsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetReceivedInvitationsResponse',
      json,
      () => GetReceivedInvitationsResponse(
        invitations: (json['invitations'] as List)
            .map<ReceivedInvitation>(
              (e) => ReceivedInvitation.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetReceivedInvitationsResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetReceivedInvitationsResponse.fromJson(json);
  }

  /// The invitations on this page, most recently sent first.
  final List<ReceivedInvitation> invitations;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page. Absent on the last page.
  final String? nextCursor;

  /// Converts a [GetReceivedInvitationsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'invitations': invitations.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(invitations),
    nextCursor,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetReceivedInvitationsResponse &&
        listsEqual(invitations, other.invitations) &&
        nextCursor == other.nextCursor;
  }
}
