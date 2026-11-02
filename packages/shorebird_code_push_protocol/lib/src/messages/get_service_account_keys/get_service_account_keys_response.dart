import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/service_account_key.dart';

/// {@template get_service_account_keys_response}
/// The response body for GET
/// /organizations/{organizationId}/service-accounts/{serviceAccountId}/keys.
/// {@endtemplate}
@immutable
class GetServiceAccountKeysResponse {
  /// {@macro get_service_account_keys_response}
  const GetServiceAccountKeysResponse({
    required this.keys,
    this.nextCursor,
    this.totalCount,
  });

  /// Converts a `Map<String, dynamic>` to a [GetServiceAccountKeysResponse].
  factory GetServiceAccountKeysResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetServiceAccountKeysResponse',
      json,
      () => GetServiceAccountKeysResponse(
        keys: (json['keys'] as List)
            .map<ServiceAccountKey>(
              (e) => ServiceAccountKey.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
        totalCount: json['total_count'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetServiceAccountKeysResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetServiceAccountKeysResponse.fromJson(json);
  }

  /// The service account's unrevoked keys, newest first.
  final List<ServiceAccountKey> keys;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page`,
  /// `cursor` or `page`) and another page follows. Absent on the last
  /// page and on unpaginated responses.
  final String? nextCursor;

  /// How many items the whole list holds. Present only when the
  /// request was paginated.
  final int? totalCount;

  /// Converts a [GetServiceAccountKeysResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'keys': keys.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
      'total_count': ?totalCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(keys),
    nextCursor,
    totalCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetServiceAccountKeysResponse &&
        listsEqual(keys, other.keys) &&
        nextCursor == other.nextCursor &&
        totalCount == other.totalCount;
  }
}
