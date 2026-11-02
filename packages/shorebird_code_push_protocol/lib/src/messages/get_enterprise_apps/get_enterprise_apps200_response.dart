import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_app.dart';

@immutable
class GetEnterpriseApps200Response {
  const GetEnterpriseApps200Response({
    required this.totalCount,
    required this.apps,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetEnterpriseApps200Response].
  factory GetEnterpriseApps200Response.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetEnterpriseApps200Response',
      json,
      () => GetEnterpriseApps200Response(
        totalCount: json['total_count'] as int,
        nextCursor: json['next_cursor'] as String?,
        apps: (json['apps'] as List)
            .map<EnterpriseApp>(
              (e) => EnterpriseApp.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetEnterpriseApps200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseApps200Response.fromJson(json);
  }

  /// How many items the whole list holds.
  final int totalCount;

  /// The cursor of the next page; absent on the last page.
  final String? nextCursor;
  final List<EnterpriseApp> apps;

  /// Converts a [GetEnterpriseApps200Response] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'total_count': totalCount,
      'next_cursor': ?nextCursor,
      'apps': apps.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    totalCount,
    nextCursor,
    listHash(apps),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetEnterpriseApps200Response &&
        totalCount == other.totalCount &&
        nextCursor == other.nextCursor &&
        listsEqual(apps, other.apps);
  }
}
