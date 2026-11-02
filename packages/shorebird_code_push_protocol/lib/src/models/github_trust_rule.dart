import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template github_trust_rule}
/// The GitHub Actions workflow an OIDC trust rule lets in. A token
/// matches when its repository (ignoring case), owner id and workflow
/// file match, and its environment and ref match when the rule names
/// them.
/// {@endtemplate}
@immutable
class GithubTrustRule {
  /// {@macro github_trust_rule}
  const GithubTrustRule({
    required this.repositoryOwner,
    required this.repositoryOwnerId,
    required this.repositoryName,
    required this.workflowPath,
    required this.environment,
    required this.refPattern,
  });

  /// Converts a `Map<String, dynamic>` to a [GithubTrustRule].
  factory GithubTrustRule.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GithubTrustRule',
      json,
      () => GithubTrustRule(
        repositoryOwner: json['repository_owner'] as String,
        repositoryOwnerId: json['repository_owner_id'] as int,
        repositoryName: json['repository_name'] as String,
        workflowPath: json['workflow_path'] as String,
        environment: checkedKey(json, 'environment') as String?,
        refPattern: checkedKey(json, 'ref_pattern') as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GithubTrustRule? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GithubTrustRule.fromJson(json);
  }

  /// The repository owner's GitHub login, as entered.
  final String repositoryOwner;

  /// GitHub's numeric id for the repository owner, resolved when the
  /// rule was added and matched against the token's
  /// `repository_owner_id` claim.
  final int repositoryOwnerId;

  /// The repository's name, as entered.
  final String repositoryName;

  /// The workflow file, such as `.github/workflows/release.yml`,
  /// matched against the path in the token's `job_workflow_ref` claim.
  final String workflowPath;

  /// The GitHub environment the job must run in, compared ignoring
  /// case, or null for any.
  final String? environment;

  /// The ref the job must run on: exact (`refs/heads/main`), or a
  /// prefix ending in `*` (`refs/tags/*`). Null for any.
  final String? refPattern;

  /// Converts a [GithubTrustRule] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'repository_owner': repositoryOwner,
      'repository_owner_id': repositoryOwnerId,
      'repository_name': repositoryName,
      'workflow_path': workflowPath,
      'environment': environment,
      'ref_pattern': refPattern,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    repositoryOwner,
    repositoryOwnerId,
    repositoryName,
    workflowPath,
    environment,
    refPattern,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GithubTrustRule &&
        repositoryOwner == other.repositoryOwner &&
        repositoryOwnerId == other.repositoryOwnerId &&
        repositoryName == other.repositoryName &&
        workflowPath == other.workflowPath &&
        environment == other.environment &&
        refPattern == other.refPattern;
  }
}
