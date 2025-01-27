import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/plist.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Checks that the macOS app has the network client entitlement. Without this
/// entitlement, the app will not be able to make network requests, and
/// Shorebird will not be able to check for patches.
class MacosEntitlementsValidator extends Validator {
  /// The entitlements plist key for the Outgoing Connections (Client)
  /// entitlement, which allows macOS apps to make network requests.
  static const networkClientEntitlementKey =
      'com.apple.security.network.client';

  /// The entitlements plist key for the Allow Unsigned Executable Memory
  /// entitlement, which allows the app to run code not included in the original
  /// binary (e.g. patches).
  static const allowUnsignedExecutableMemoryKey =
      'com.apple.security.cs.allow-unsigned-executable-memory';

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
  String get description => 'macOS app has correct entitlements';

  @override
  bool canRunInCurrentContext() => _macosDirectory?.existsSync() ?? false;

  @override
  String? get incorrectContextMessage => '''
The ${_macosDirectory?.path ?? 'macos'} directory does not exist.

The command you are running must be run within a Flutter app project that supports the macOS platform.''';

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

    final issues = <ValidationIssue>[];
    if (!hasNetworkClientEntitlement(plistFile: _releaseEntitlementsPlist!)) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message:
              '''${_releaseEntitlementsPlist!.path} is missing the Outgoing Connections ($networkClientEntitlementKey) entitlement.''',
          fix: () => addNetworkEntitlementToPlist(_releaseEntitlementsPlist!),
        ),
      );
    }

    if (!hasAllowUnsignedExecutableMemoryEntitlement(
      plistFile: _releaseEntitlementsPlist!,
    )) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message:
              '''${_releaseEntitlementsPlist!.path} is missing the Allow Unsigned Executable Memory ($allowUnsignedExecutableMemoryKey) entitlement.''',
          fix: () => addAllowUnsignedExecutableMemoryEntitlementToPlist(
            _releaseEntitlementsPlist!,
          ),
        ),
      );
    }

    return issues;
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

  /// Whether the given entitlements plist file has the allow unsigned
  /// executable memory entitlement.
  @visibleForTesting
  static bool hasAllowUnsignedExecutableMemoryEntitlement({
    required File plistFile,
  }) {
    return Plist(file: plistFile)
            .properties[allowUnsignedExecutableMemoryKey] ==
        true;
  }

  /// Adds the allow unsigned executable memory entitlement to the given
  /// entitlements plist file.
  @visibleForTesting
  static void addAllowUnsignedExecutableMemoryEntitlementToPlist(
    File entitlementsPlist,
  ) {
    final plist = Plist(file: entitlementsPlist);
    plist.properties[allowUnsignedExecutableMemoryKey] = true;
    entitlementsPlist.writeAsStringSync(plist.toString());
  }
}
