import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/plist.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Checks that the macOS app has the network client entitlement. Without this
/// entitlement, the app will not be able to make network requests, and
/// Shorebird will not be able to check for patches.
class MacosNetworkEntitlementValidator extends Validator {
  /// The plist key for the Outgoing Connections (Client) entitlement, which
  /// allows macOS apps to make network requests.
  static const networkClientEntitlementKey =
      'com.apple.security.network.client';

  Directory? get _macosDirectory {
    final projectRoot = shorebirdEnv.getFlutterProjectRoot();
    if (projectRoot == null) {
      return null;
    }

    return Directory(p.join(projectRoot.path, 'macos'));
  }

  /// The entitlements plist file for the release build. This lives in
  /// project_root/macos/Runner/Release.entitlements, where "Runner" may have
  /// been renamed.
  File? get _releaseEntitlementsPlist {
    final entitlementParentCandidateDirectories =
        _macosDirectory!.listSync().whereType<Directory>();

    for (final appDir in entitlementParentCandidateDirectories) {
      final entitlementsPlist = File(
        p.join(appDir.path, 'Release.entitlements'),
      );

      if (entitlementsPlist.existsSync()) {
        return entitlementsPlist;
      }
    }

    return null;
  }

  @override
  String get description => 'macOS app has Outgoing Connections entitlement';

  @override
  bool canRunInCurrentContext() =>
      _macosDirectory != null && _macosDirectory!.existsSync();

  @override
  Future<List<ValidationIssue>> validate() async {
    if (_releaseEntitlementsPlist == null) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Unable to find a Release.entitlements file',
        ),
      ];
    }

    if (!hasNetworkClientEntitlement(plistFile: _releaseEntitlementsPlist!)) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message:
              '''${_releaseEntitlementsPlist!.path} is missing the Outgoing Connections ($networkClientEntitlementKey) entitlement.''',
          fix: () => addNetworkEntitlementToPlist(_releaseEntitlementsPlist!),
        ),
      ];
    }

    return [];
  }

  /// Whether the given entitlements plist file has the network client
  /// entitlement.
  @visibleForTesting
  static bool hasNetworkClientEntitlement({required File plistFile}) =>
      Plist(file: plistFile).properties[networkClientEntitlementKey] == true;

  /// Adds the network client entitlement to the given entitlements plist file.
  @visibleForTesting
  static void addNetworkEntitlementToPlist(File entitlementsPlist) {
    final plist = Plist(file: entitlementsPlist);
    plist.properties[networkClientEntitlementKey] = true;
    entitlementsPlist.writeAsStringSync(plist.toString());
  }
}
