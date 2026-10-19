import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/organization_id.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/pubspec_editor.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// {@template init_command}
///
/// `shorebird init`
/// Initialize Shorebird.
/// {@endtemplate}
class InitCommand extends ShorebirdCommand {
  /// {@macro init_command}
  InitCommand() {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Initialize the app even if a "shorebird.yaml" already exists.',
        negatable: false,
      )
      ..addOption(
        'display-name',
        help:
            'The app name shown in the Shorebird dashboard '
            '(defaults to the package name in pubspec.yaml). '
            'Must be between 1 and '
            '${CommonArguments.appDisplayNameMaxLength} characters.',
      )
      // `--organization-id` was this command's original name; kept as a
      // hidden alias so existing scripts keep working.
      ..addOption(
        CommonArguments.orgIdArg.name,
        aliases: const ['organization-id'],
        help: 'The id of the organization the app belongs to (e.g. "42").',
      );
  }

  @override
  String get description => 'Initialize Shorebird.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return reportPreconditionFailure(e);
    }

    try {
      if (!shorebirdEnv.hasPubspecYaml) {
        logger.err('''
Could not find a "pubspec.yaml".
Please make sure you are running "shorebird init" from within your Flutter project.
''');
        return ExitCode.noInput.code;
      }
    } on Exception catch (error) {
      logger
        ..err('Error parsing "pubspec.yaml": $error')
        ..info('Fix the YAML error above and re-run "shorebird init".');
      return ExitCode.software.code;
    }

    final organizationMemberships = await codePushClientWrapper
        .getOrganizationMemberships();
    if (organizationMemberships.isEmpty) {
      logger.err(
        '''You do not have any organizations. This should never happen. Please contact us on Discord or send us an email at contact@shorebird.dev.''',
      );
      return ExitCode.software.code;
    }
    // Checked up front so a bad --org-id fails before any slow setup.
    final namedMembership = _membershipNamedByOrgId(organizationMemberships);

    final force = results['force'] == true;

    Set<String>? androidFlavors;
    Set<String>? iosFlavors;
    Set<String>? macosFlavors;
    var productFlavors = <String>{};
    final projectRoot = shorebirdEnv.getFlutterProjectRoot()!;
    final initializeGradleProgress = logger.progress('Initializing gradlew');
    final bool shouldStartGradleDaemon;
    try {
      shouldStartGradleDaemon = await _shouldStartGradleDaemon(
        projectRoot.path,
      );
    } on Exception catch (error) {
      initializeGradleProgress.fail();
      logger
        ..err('Unable to initialize gradlew: $error')
        ..info(
          '''Fix the Gradle error above (run ${lightCyan.wrap('./gradlew --status')} in the android directory to reproduce it), then re-run "shorebird init".''',
        );
      return ExitCode.software.code;
    }
    initializeGradleProgress.complete();

    if (shouldStartGradleDaemon) {
      try {
        await gradlew.startDaemon(projectRoot.path);
      } on Exception catch (error) {
        logger
          ..err('Unable to start the gradle daemon: $error')
          ..info(
            '''Fix the Gradle error above (run ${lightCyan.wrap('./gradlew --daemon')} in the android directory to reproduce it), then re-run "shorebird init".''',
          );
        return ExitCode.software.code;
      }
    }

    final detectFlavorsProgress = logger.progress('Detecting product flavors');
    try {
      androidFlavors = await _maybeGetAndroidFlavors(projectRoot.path);
      iosFlavors = apple.flavors(platform: ApplePlatform.ios);
      macosFlavors = apple.flavors(platform: ApplePlatform.macos);
      productFlavors = <String>{
        ...?androidFlavors,
        ...?iosFlavors,
        ...?macosFlavors,
      };
      if (productFlavors.isEmpty) {
        detectFlavorsProgress.complete('No product flavors detected.');
      } else {
        detectFlavorsProgress.complete(
          '${productFlavors.length} product flavors detected:',
        );
        for (final flavor in productFlavors) {
          logger.info('  - $flavor');
        }
      }
    } on Exception catch (error) {
      detectFlavorsProgress.fail();
      logger
        ..err('Unable to detect product flavors.\n$error')
        ..info(
          '''Fix the build error above (run ${lightCyan.wrap('./gradlew app:tasks --all')} in the android directory to reproduce it), then re-run "shorebird init".''',
        );
      return ExitCode.software.code;
    }

    final shorebirdYaml = shorebirdEnv.getShorebirdYaml();
    final existingFlavors = shorebirdYaml?.flavors;
    Set<String> newFlavors;
    if (existingFlavors != null) {
      final existingFlavorNames = existingFlavors.keys.toSet();
      newFlavors = productFlavors.difference(existingFlavorNames);
    } else if (shorebirdYaml != null) {
      // Existing shorebird.yaml without flavors — treat all detected flavors
      // as new so they can be added without resetting the base app_id.
      newFlavors = productFlavors;
    } else {
      newFlavors = {};
    }

    // New flavors not being empty means that there is already an existing app
    // and we just need to add the new flavor entries.
    // If the --force flag is present, we will completely reinit the app and
    // don't care about which flavors are new.
    if (!force && newFlavors.isNotEmpty) {
      logger.info('New flavors detected: ${newFlavors.join(', ')}');

      // maybeGetApp rather than getApp, because getApp reports a missing app
      // and a failed lookup the same way -- both exit through ProcessExit --
      // and the remedy below is only right for the first. A network failure,
      // an expired token, or a required upgrade still exits from the fetch
      // with its own message, and without advice about app_id.
      final existingApp = await codePushClientWrapper.maybeGetApp(
        appId: shorebirdYaml!.appId,
      );
      if (existingApp == null) {
        logger
          ..err('''
Could not find app with id: "${shorebirdYaml.appId}".
This app may not exist or you may not have permission to view it.''')
          ..info(
            '''Fix the app_id in shorebird.yaml, or run ${lightCyan.wrap('shorebird init --force')} to create a new app.''',
          );
        return ExitCode.software.code;
      }

      // Flavor apps belong with the app they are flavors of, wherever that
      // is, rather than wherever a new app would go.
      final appMembership = await codePushClientWrapper.findAppOrganization(
        appId: existingApp.appId,
        organizationId: existingApp.organizationId,
        memberships: organizationMemberships,
      );
      if (appMembership == null && existingApp.organizationId != null) {
        logger
          ..err(
            'App "${existingApp.displayName}" (${existingApp.appId}) is in '
            'organization ${existingApp.organizationId}, which you are not a '
            'member of.',
          )
          ..info(
            'Ask an owner or admin of that organization to add you, then run '
            'init again.',
          );
        return ExitCode.noPerm.code;
      }
      if (appMembership == null) {
        logger
          ..err(
            'Could not find which of your organizations app '
            '"${existingApp.displayName}" (${existingApp.appId}) is in.',
          )
          ..info(
            '''Check the app_id in shorebird.yaml, or run ${lightCyan.wrap('shorebird init --force')} to create a new app.''',
          );
        return ExitCode.software.code;
      }
      final organization = appMembership.organization;
      if (!_canCreateApps(appMembership.role)) {
        logger
          ..err(
            'You cannot create apps in ${_describe(organization)}, which '
            '"${existingApp.displayName}" is in: ${_roleIn(appMembership)}.',
          )
          ..info(_askForRole);
        return ExitCode.noPerm.code;
      }
      if (namedMembership != null &&
          namedMembership.organization.id != organization.id) {
        logger.warn(
          'Ignoring --${CommonArguments.orgIdArg.name}: new flavors go in '
          '${_describe(organization)} with "${existingApp.displayName}".',
        );
      }

      final updateShorebirdYamlProgress = logger.progress(
        'Adding flavors to shorebird.yaml',
      );

      final deflavoredAppName = existingApp.displayName
          .replaceAll(RegExp(r'\(.*\)'), '')
          .trim();
      final flavorsToAppIds = shorebirdYaml.flavors ?? {};
      for (final flavor in newFlavors) {
        final app = await codePushClientWrapper.createApp(
          appName: '$deflavoredAppName ($flavor)',
          organizationId: organization.id,
        );
        flavorsToAppIds[flavor] = app.id;
      }
      _addShorebirdYamlToProject(
        projectRoot: projectRoot,
        appId: shorebirdYaml.appId,
        flavors: flavorsToAppIds,
      );
      updateShorebirdYamlProgress.complete('Flavors added to shorebird.yaml');
      return ExitCode.success.code;
    }

    if (!force && shorebirdEnv.hasShorebirdYaml) {
      logger
        ..err('A "shorebird.yaml" file already exists and seems up-to-date.')
        ..info(
          '''If you want to reinitialize Shorebird, please run ${lightCyan.wrap('shorebird init --force')}.''',
        );
      return ExitCode.software.code;
    }

    final organization = _chooseOrganization(
      organizationMemberships,
      named: namedMembership,
    );
    if (organization == null) return ExitCode.noPerm.code;

    final needsConfirmation = !force && shorebirdEnv.canAcceptUserInput;
    final pubspecName = shorebirdEnv.getPubspecYaml()!.name;
    var displayName = results['display-name'] as String?;
    displayName ??= needsConfirmation
        ? logger.prompt(
            '${lightGreen.wrap('?')} How should we refer to this app?',
            defaultValue: pubspecName,
            hint:
                'Pass --display-name=<name> to set the app name without '
                'prompting.',
          )
        : pubspecName;
    final nameError = CommonArguments.nameError(
      label: 'App display name',
      value: displayName,
      maxLength: CommonArguments.appDisplayNameMaxLength,
    );
    if (nameError != null) usageException(nameError);

    final String appId;
    Map<String, String>? flavors;
    try {
      final hasNoFlavors = productFlavors.isEmpty;
      final hasSomeFlavors =
          productFlavors.isNotEmpty &&
          ((androidFlavors?.isEmpty ?? false) ||
              (iosFlavors?.isEmpty ?? false));

      if (hasNoFlavors) {
        // No platforms have any flavors so we just create a single app
        // and assign it as the default.
        final app = await codePushClientWrapper.createApp(
          appName: displayName,
          organizationId: organization.id,
        );
        appId = app.id;
      } else if (hasSomeFlavors) {
        // Some platforms have flavors and some do not so we create an app
        // for the default (no flavor) and then create an app per flavor.
        final app = await codePushClientWrapper.createApp(
          appName: displayName,
          organizationId: organization.id,
        );
        appId = app.id;
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          final app = await codePushClientWrapper.createApp(
            appName: '$displayName ($flavor)',
            organizationId: organization.id,
          );
          values[flavor] = app.id;
        }
        flavors = values;
      } else {
        // All platforms have flavors so we create an app per flavor
        // and assign the default to the first flavor.
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          final app = await codePushClientWrapper.createApp(
            appName: '$displayName ($flavor)',
            organizationId: organization.id,
          );
          values[flavor] = app.id;
        }
        flavors = values;
        appId = flavors.values.first;
      }
    } on Exception catch (error) {
      logger
        ..err('Failed to create the app: $error')
        ..info(
          '''Re-run "shorebird init" once the error above is resolved. If it persists, contact us on Discord or at contact@shorebird.dev.''',
        );
      return ExitCode.software.code;
    }

    _addShorebirdYamlToProject(
      projectRoot: projectRoot,
      appId: appId,
      flavors: flavors,
    );

    if (!shorebirdEnv.pubspecContainsShorebirdYaml) {
      pubspecEditor.addShorebirdYamlToPubspecAssets();
    }

    logger.info(
      '''

${lightGreen.wrap('🐦 Shorebird initialized successfully!')}

✅ A shorebird app has been created.
✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.

Reference the following commands to get started:

📦 To create a new release use: "${lightCyan.wrap('shorebird release')}".
🚀 To push an update use: "${lightCyan.wrap('shorebird patch')}".
👀 To preview a release use: "${lightCyan.wrap('shorebird preview')}".

For more information about Shorebird, visit ${link(uri: Uri.parse('https://shorebird.dev'))}''',
    );

    await doctor.runValidators(
      doctor.initAndDoctorValidators,
      applyFixes: true,
    );

    return ExitCode.success.code;
  }

  Future<bool> _shouldStartGradleDaemon(String projectPath) async {
    try {
      final isAvailable = await gradlew.isDaemonAvailable(projectPath);
      return !isAvailable;
    } on MissingAndroidProjectException {
      return false;
    }
  }

  Future<Set<String>?> _maybeGetAndroidFlavors(String projectPath) async {
    try {
      return await gradlew.productFlavors(projectPath);
    } on MissingAndroidProjectException {
      return null;
    }
  }

  /// The membership `--org-id` names among [memberships], or null without
  /// `--org-id`. Throws a usage exception when it names no organization the
  /// user is in.
  OrganizationMembership? _membershipNamedByOrgId(
    List<OrganizationMembership> memberships,
  ) {
    final orgIdArg = results[CommonArguments.orgIdArg.name] as String?;
    if (orgIdArg == null) return null;
    final (id: orgId, error: parseError) = parseOrganizationId(
      orgIdArg,
      memberships: memberships,
    );
    if (parseError != null) {
      usageException('${parseError.message}\n${parseError.hint}');
    }
    final (:membership, error: membershipError) = findOrganizationMembership(
      id: orgId!,
      memberships: memberships,
    );
    if (membershipError != null) {
      usageException('${membershipError.message}\n${membershipError.hint}');
    }
    return membership;
  }

  /// Chooses the organization a new app goes in, from [memberships]: the
  /// [named] one (from `--org-id`), the only one the user can create apps in,
  /// or the one they pick. Returns null, having said why, when the user
  /// cannot create apps in it.
  Organization? _chooseOrganization(
    List<OrganizationMembership> memberships, {
    required OrganizationMembership? named,
  }) {
    // Only these roles hold the server's create-apps permission; offering
    // other organizations would just defer the refusal to createApp.
    final creatableMemberships = memberships
        .where((m) => _canCreateApps(m.role))
        .toList();
    final skippedMemberships = memberships
        .where((m) => !_canCreateApps(m.role))
        .toList();

    if (named != null) {
      final membership = named;
      if (!_canCreateApps(membership.role)) {
        logger
          ..err(
            'You cannot create apps in ${_describe(membership.organization)}: '
            '${_roleIn(membership)}.',
          )
          ..info(
            creatableMemberships.isEmpty
                ? _askForRole
                : availableOrganizations(
                    creatableMemberships,
                    label: _creatableLabel,
                  ),
          );
        return null;
      }
      return membership.organization;
    } else if (creatableMemberships.isEmpty) {
      logger
        ..err('You cannot create apps in any of your organizations.')
        ..info(
          '${_rolesIn(memberships)}\n$_askForRole',
        );
      return null;
    } else {
      if (skippedMemberships.isNotEmpty) {
        logger.info(
          'Skipping organizations you cannot create apps in. '
          '${_rolesIn(skippedMemberships)}',
        );
      }
      if (creatableMemberships.length > 1) {
        if (!shorebirdEnv.canAcceptUserInput) {
          final creatable = availableOrganizations(
            creatableMemberships,
            label: _creatableLabel,
          );
          usageException(
            'You can create apps in multiple organizations. '
            'Pass --org-id=<id> to choose one.\n$creatable',
          );
        }
        return logger.chooseOne<Organization>(
          'Which organization should this app belong to?',
          choices: creatableMemberships.map((o) => o.organization).toList(),
          display: (o) => o.name,
          hint:
              'Pass --org-id=<id> to select an organization without '
              'prompting.',
        );
      } else {
        final organization = creatableMemberships.single.organization;
        if (skippedMemberships.isNotEmpty) {
          logger.info(
            'Creating the app in ${_describe(organization)}, the only '
            'organization you can create apps in.',
          );
        }
        return organization;
      }
    }
  }

  ShorebirdYaml _addShorebirdYamlToProject({
    required String appId,
    required Directory projectRoot,
    Map<String, String>? flavors,
  }) {
    const content =
        '''
# This file is used to configure the Shorebird updater used by your app.
# Learn more at $docsUrl
# This file does not contain any sensitive information and should be checked into version control.

# Your app_id is the unique identifier assigned to your app.
# It is used to identify your app when requesting patches from Shorebird's servers.
# It is not a secret and can be shared publicly.
app_id:

# auto_update controls if Shorebird should automatically update in the background on launch.
# If auto_update: false, you will need to use package:shorebird_code_push to trigger updates.
# https://pub.dev/packages/shorebird_code_push
# Uncomment the following line to disable automatic updates.
# auto_update: false
''';

    final editor = YamlEditor(content)..update(['app_id'], appId);

    if (flavors != null) editor.update(['flavors'], flavors);

    shorebirdEnv
        .getShorebirdYamlFile(cwd: projectRoot)
        .writeAsStringSync(editor.toString());

    return ShorebirdYaml(appId: appId);
  }
}

/// Whether [role] in an organization lets its holder create apps there,
/// matching the server's `create(apps)` permission.
bool _canCreateApps(Role role) =>
    role == Role.owner || role == Role.admin || role == Role.appManager;

const _creatableLabel = 'Organizations you can create apps in';

const _askForRole =
    'Ask an owner or admin of the organization to make you an admin.';

String _describe(Organization organization) =>
    '${organization.name} (id: ${organization.id})';

/// The user's standing in [membership]'s organization, in words.
///
/// [Role.none] means the user only reaches the organization through a role
/// granted on one of its apps, so they are not a member at all.
String _roleIn(OrganizationMembership membership) =>
    membership.role == Role.none
    ? 'you are not a member, you only have access to some of its apps'
    : 'your role is ${membership.role}';

/// Lists the user's standing in each of [memberships]' organizations.
String _rolesIn(List<OrganizationMembership> memberships) {
  final roles = memberships.map(
    (m) => '${_describe(m.organization)}: ${_roleIn(m)}',
  );
  return 'Your access: ${roles.join('; ')}.';
}
