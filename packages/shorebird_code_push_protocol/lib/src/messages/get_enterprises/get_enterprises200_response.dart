import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_membership.dart';

@immutable
class GetEnterprises200Response {
  const GetEnterprises200Response({
    required this.totalCount,
    required this.enterprises,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetEnterprises200Response].
  factory GetEnterprises200Response.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetEnterprises200Response',
      json,
      () => GetEnterprises200Response(
        totalCount: json['total_count'] as int,
        nextCursor: json['next_cursor'] as String?,
        enterprises: (json['enterprises'] as List)
            .map<EnterpriseMembership>(
              (e) => EnterpriseMembership.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetEnterprises200Response? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetEnterprises200Response.fromJson(json);
  }

  /// How many items the whole list holds.
  final int totalCount;

  /// The cursor of the next page; absent on the last page.
  final String? nextCursor;
  final List<EnterpriseMembership> enterprises;

  /// Converts a [GetEnterprises200Response] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'total_count': totalCount,
      'next_cursor': ?nextCursor,
      'enterprises': enterprises.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    totalCount,
    nextCursor,
    listHash(enterprises),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetEnterprises200Response &&
        totalCount == other.totalCount &&
        nextCursor == other.nextCursor &&
        listsEqual(enterprises, other.enterprises);
  }
}
