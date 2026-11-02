import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_app_summary.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_default_role.dart';

/// {@template enterprise_team}
/// One of an enterprise's organizations, with its counts and the apps it
/// carries, which may be only the first of `app_count`.
/// {@endtemplate}
@immutable
class EnterpriseTeam {
  /// {@macro enterprise_team}
  const EnterpriseTeam({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.appCount,
    required this.defaultRole,
    required this.apps,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseTeam].
  factory EnterpriseTeam.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseTeam',
      json,
      () => EnterpriseTeam(
        id: json['id'] as int,
        name: json['name'] as String,
        memberCount: json['member_count'] as int,
        appCount: json['app_count'] as int,
        defaultRole: EnterpriseDefaultRole.maybeFromJson(
          checkedKey(json, 'default_role') as String?,
        ),
        apps: (json['apps'] as List)
            .map<EnterpriseAppSummary>(
              (e) => EnterpriseAppSummary.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseTeam? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseTeam.fromJson(json);
  }

  final int id;
  final String name;
  final int memberCount;
  final int appCount;

  /// A role a default organization joins people at.
  final EnterpriseDefaultRole? defaultRole;
  final List<EnterpriseAppSummary> apps;

  /// Converts an [EnterpriseTeam] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'member_count': memberCount,
      'app_count': appCount,
      'default_role': defaultRole?.toJson(),
      'apps': apps.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    memberCount,
    appCount,
    defaultRole,
    listHash(apps),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseTeam &&
        id == other.id &&
        name == other.name &&
        memberCount == other.memberCount &&
        appCount == other.appCount &&
        defaultRole == other.defaultRole &&
        listsEqual(apps, other.apps);
  }
}
