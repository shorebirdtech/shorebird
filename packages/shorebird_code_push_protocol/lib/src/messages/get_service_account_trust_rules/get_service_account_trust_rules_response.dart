// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/service_account_trust_rule.dart';

/// {@template get_service_account_trust_rules_response}
/// The response body for GET
/// /organizations/{organizationId}/service-accounts/{serviceAccountId}/trust-rules.
/// {@endtemplate}
@immutable
class GetServiceAccountTrustRulesResponse {
  /// {@macro get_service_account_trust_rules_response}
  const GetServiceAccountTrustRulesResponse({
    required this.trustRules,
    this.nextCursor,
    this.totalCount,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [GetServiceAccountTrustRulesResponse].
  factory GetServiceAccountTrustRulesResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'GetServiceAccountTrustRulesResponse',
      json,
      () => GetServiceAccountTrustRulesResponse(
        trustRules: (json['trust_rules'] as List)
            .map<ServiceAccountTrustRule>(
              (e) =>
                  ServiceAccountTrustRule.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
        totalCount: json['total_count'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetServiceAccountTrustRulesResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetServiceAccountTrustRulesResponse.fromJson(json);
  }

  /// The service account's trust rules, oldest first.
  final List<ServiceAccountTrustRule> trustRules;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page`,
  /// `cursor` or `page`) and another page follows. Absent on the last
  /// page and on unpaginated responses.
  final String? nextCursor;

  /// How many items the whole list holds. Present only when the
  /// request was paginated.
  final int? totalCount;

  /// Converts a [GetServiceAccountTrustRulesResponse]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'trust_rules': trustRules.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
      'total_count': ?totalCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(trustRules),
    nextCursor,
    totalCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetServiceAccountTrustRulesResponse &&
        listsEqual(trustRules, other.trustRules) &&
        nextCursor == other.nextCursor &&
        totalCount == other.totalCount;
  }
}
