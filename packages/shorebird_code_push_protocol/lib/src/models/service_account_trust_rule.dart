import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/github_trust_rule.dart';
import 'package:shorebird_code_push_protocol/src/models/trust_rule_provider.dart';

/// {@template service_account_trust_rule}
/// An OIDC trust rule: lets a CI workflow authenticate as a service
/// account with a token from the CI provider's identity provider. The
/// provider's own fields are under the provider's name.
/// {@endtemplate}
@immutable
class ServiceAccountTrustRule {
  /// {@macro service_account_trust_rule}
  const ServiceAccountTrustRule({
    required this.id,
    required this.provider,
    required this.createdAt,
    required this.createdByUserId,
    required this.lastUsedAt,
    required this.github,
  });

  /// Converts a `Map<String, dynamic>` to a [ServiceAccountTrustRule].
  factory ServiceAccountTrustRule.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ServiceAccountTrustRule',
      json,
      () => ServiceAccountTrustRule(
        id: json['id'] as int,
        provider: TrustRuleProvider.fromJson(json['provider'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        createdByUserId: checkedKey(json, 'created_by_user_id') as int?,
        lastUsedAt: maybeParseDateTime(
          checkedKey(json, 'last_used_at') as String?,
        ),
        github: GithubTrustRule.fromJson(
          json['github'] as Map<String, dynamic>,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ServiceAccountTrustRule? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ServiceAccountTrustRule.fromJson(json);
  }

  /// The trust rule's ID.
  final int id;

  /// The identity provider whose tokens an OIDC trust rule accepts.
  final TrustRuleProvider provider;

  /// When the rule was added.
  final DateTime createdAt;

  /// The user who added the rule, or null once that user has been
  /// deleted.
  final int? createdByUserId;

  /// When a token was last exchanged under the rule, or null if never.
  final DateTime? lastUsedAt;

  /// The GitHub Actions workflow an OIDC trust rule lets in. A token
  /// matches when its repository (ignoring case), owner id and workflow
  /// file match, and its environment and ref match when the rule names
  /// them.
  final GithubTrustRule github;

  /// Converts a [ServiceAccountTrustRule] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider.toJson(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'created_by_user_id': createdByUserId,
      'last_used_at': lastUsedAt?.toUtc().toIso8601String(),
      'github': github.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    provider,
    createdAt,
    createdByUserId,
    lastUsedAt,
    github,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServiceAccountTrustRule &&
        id == other.id &&
        provider == other.provider &&
        createdAt == other.createdAt &&
        createdByUserId == other.createdByUserId &&
        lastUsedAt == other.lastUsedAt &&
        github == other.github;
  }
}
