import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template invitation_summary}
/// A pending invitation, as listed to the people who manage it.
/// {@endtemplate}
@immutable
class InvitationSummary {
  /// {@macro invitation_summary}
  const InvitationSummary({
    required this.id,
    required this.email,
    required this.role,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Converts a `Map<String, dynamic>` to an [InvitationSummary].
  factory InvitationSummary.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'InvitationSummary',
      json,
      () => InvitationSummary(
        id: json['id'] as String,
        email: json['email'] as String,
        role: Role.fromJson(json['role'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static InvitationSummary? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return InvitationSummary.fromJson(json);
  }

  /// The ID of the invitation, which revoking it takes.
  final String id;

  /// The email the invitation was sent to.
  final String email;

  /// The role the invitee gets on accepting.
  final Role role;

  /// When the invitation was sent.
  final DateTime createdAt;

  /// When the invitation stops being valid.
  final DateTime expiresAt;

  /// Converts an [InvitationSummary] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role.toJson(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    email,
    role,
    createdAt,
    expiresAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InvitationSummary &&
        id == other.id &&
        email == other.email &&
        role == other.role &&
        createdAt == other.createdAt &&
        expiresAt == other.expiresAt;
  }
}
