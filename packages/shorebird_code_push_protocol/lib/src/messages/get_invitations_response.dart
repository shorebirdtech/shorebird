import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/invitation_summary.dart';

/// {@template get_invitations_response}
/// The response body for listing the pending invitations to an
/// organization or an app.
/// {@endtemplate}
@immutable
class GetInvitationsResponse {
  /// {@macro get_invitations_response}
  const GetInvitationsResponse({
    required this.invitations,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetInvitationsResponse].
  factory GetInvitationsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetInvitationsResponse',
      json,
      () => GetInvitationsResponse(
        invitations: (json['invitations'] as List)
            .map<InvitationSummary>(
              (e) => InvitationSummary.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetInvitationsResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetInvitationsResponse.fromJson(json);
  }

  /// The invitations on this page, most recently sent first.
  final List<InvitationSummary> invitations;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page. Absent on the last page.
  final String? nextCursor;

  /// Converts a [GetInvitationsResponse] to a `Map<String, dynamic>`.
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
    return other is GetInvitationsResponse &&
        listsEqual(invitations, other.invitations) &&
        nextCursor == other.nextCursor;
  }
}
