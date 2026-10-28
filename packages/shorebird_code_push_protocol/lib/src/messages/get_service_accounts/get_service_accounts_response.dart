import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/service_account.dart';

/// {@template get_service_accounts_response}
/// The response body for GET /organizations/{organizationId}/service-accounts.
/// {@endtemplate}
@immutable
class GetServiceAccountsResponse {
  /// {@macro get_service_accounts_response}
  const GetServiceAccountsResponse({
    required this.serviceAccounts,
    this.nextCursor,
    this.totalCount,
  });

  /// Converts a `Map<String, dynamic>` to a [GetServiceAccountsResponse].
  factory GetServiceAccountsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetServiceAccountsResponse',
      json,
      () => GetServiceAccountsResponse(
        serviceAccounts: (json['service_accounts'] as List)
            .map<ServiceAccount>(
              (e) => ServiceAccount.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
        totalCount: json['total_count'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetServiceAccountsResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetServiceAccountsResponse.fromJson(json);
  }

  /// The organization's service accounts, oldest first.
  final List<ServiceAccount> serviceAccounts;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page`,
  /// `cursor` or `page`) and another page follows. Absent on the last
  /// page and on unpaginated responses.
  final String? nextCursor;

  /// How many items the whole list holds. Present only when the
  /// request was paginated.
  final int? totalCount;

  /// Converts a [GetServiceAccountsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'service_accounts': serviceAccounts.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
      'total_count': ?totalCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(serviceAccounts),
    nextCursor,
    totalCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetServiceAccountsResponse &&
        listsEqual(serviceAccounts, other.serviceAccounts) &&
        nextCursor == other.nextCursor &&
        totalCount == other.totalCount;
  }
}
