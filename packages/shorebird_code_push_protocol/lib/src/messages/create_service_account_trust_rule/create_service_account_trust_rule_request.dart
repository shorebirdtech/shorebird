// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/trust_rule_provider.dart';

/// {@template create_service_account_trust_rule_request}
/// The request body for POST
/// /organizations/{organizationId}/service-accounts/{serviceAccountId}/trust-rules.
/// Unlike `ServiceAccountTrustRule`, the GitHub fields sit at the top
/// level rather than under `github`.
/// {@endtemplate}
@immutable
class CreateServiceAccountTrustRuleRequest {
  /// {@macro create_service_account_trust_rule_request}
  const CreateServiceAccountTrustRuleRequest({
    required this.provider,
    required this.repositoryOwner,
    required this.repositoryName,
    required this.workflowPath,
    this.environment,
    this.refPattern,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [CreateServiceAccountTrustRuleRequest].
  factory CreateServiceAccountTrustRuleRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'CreateServiceAccountTrustRuleRequest',
      json,
      () => CreateServiceAccountTrustRuleRequest(
        provider: TrustRuleProvider.fromJson(json['provider'] as String),
        repositoryOwner: json['repository_owner'] as String,
        repositoryName: json['repository_name'] as String,
        workflowPath: json['workflow_path'] as String,
        environment: json['environment'] as String?,
        refPattern: json['ref_pattern'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateServiceAccountTrustRuleRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateServiceAccountTrustRuleRequest.fromJson(json);
  }

  /// The identity provider whose tokens an OIDC trust rule accepts.
  final TrustRuleProvider provider;

  /// The login of the GitHub user or organization that owns the
  /// repository: letters, digits and hyphens, starting with a letter
  /// or digit, at most 39 characters
  /// (`^[A-Za-z0-9][A-Za-z0-9-]{0,38}$`). Must exist on GitHub; the
  /// server resolves it to its numeric id.
  final String repositoryOwner;

  /// The repository's name: 1 to 100 letters, digits, `.`, `-` or
  /// `_` (`^[A-Za-z0-9._-]{1,100}$`), and neither `.` nor `..`.
  final String repositoryName;

  /// The workflow file, directly in `.github/workflows/` and ending
  /// `.yml` or `.yaml`, such as `.github/workflows/release.yml`. May
  /// not contain `..`.
  final String workflowPath;

  /// The GitHub environment the job must run in: 1 to 255 characters,
  /// without surrounding spaces. Omitted or null accepts any
  /// environment.
  final String? environment;

  /// The ref the job must run on, at most 255 characters: exact
  /// (`refs/heads/main`), or a prefix ending in a single `*`
  /// (`refs/tags/*`), with no other `*` and no whitespace. Omitted or
  /// null accepts any ref.
  final String? refPattern;

  /// Converts a [CreateServiceAccountTrustRuleRequest]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'provider': provider.toJson(),
      'repository_owner': repositoryOwner,
      'repository_name': repositoryName,
      'workflow_path': workflowPath,
      'environment': environment,
      'ref_pattern': refPattern,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    provider,
    repositoryOwner,
    repositoryName,
    workflowPath,
    environment,
    refPattern,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateServiceAccountTrustRuleRequest &&
        provider == other.provider &&
        repositoryOwner == other.repositoryOwner &&
        repositoryName == other.repositoryName &&
        workflowPath == other.workflowPath &&
        environment == other.environment &&
        refPattern == other.refPattern;
  }
}
