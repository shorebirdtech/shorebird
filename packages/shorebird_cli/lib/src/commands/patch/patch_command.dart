import 'dart:io';

import 'package:archive/archive.dart' show ArchiveException;
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_session.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/build_flags.dart';
import 'package:shorebird_cli/src/build_history.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
import 'package:shorebird_cli/src/extensions/release_patch.dart';
import 'package:shorebird_cli/src/extensions/string.dart';
import 'package:shorebird_cli/src/extensions/version.dart';
import 'package:shorebird_cli/src/flutter_build_options.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/patch_verification.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_chooser.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/rollout_percentage.dart';
import 'package:shorebird_cli/src/rollout_schedule.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/split_debug_info.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Signature for a function that returns a [Patcher] for a given [ReleaseType].
typedef ResolvePatcher = Patcher Function(ReleaseType releaseType);

/// Added to the hint for a patch blocked by native changes.
const _nativeCrashWarning =
    "\nOnly do this if your Dart code doesn't depend on the native changes: "
    "a mismatch between your Dart code and the release's native code can "
    'crash your app.';

/// {@template patch_command}
/// A command that creates a shorebird patch for the provided target platforms.
/// `shorebird patch --platforms=android,ios`
/// {@endtemplate}
class PatchCommand extends ShorebirdCommand {
  /// {@macro patch_command}
  PatchCommand({ResolvePatcher? resolvePatcher}) {
    _resolvePatcher = resolvePatcher ?? getPatcher;
    argParser
      ..addMultiOption(
        CommonArguments.dartDefineArg.name,
        abbr: 'D',
        splitCommas: false,
        help: CommonArguments.dartDefineArg.description,
      )
      ..addMultiOption(
        CommonArguments.dartDefineFromFileArg.name,
        help: CommonArguments.dartDefineFromFileArg.description,
      )
      ..addMultiOption(
        'platforms',
        abbr: 'p',
        help: 'The platform(s) to build this patch for.',
        allowed: ReleaseType.values.map((e) => e.cliName).toList(),
      )
      ..addOption(
        patchKeyArgName,
        help:
            'Give this patch the same patch number as patches for other '
            'platforms published with the same key on the release. Defaults '
            "to the commit's SHA when the git working tree is clean.",
        valueHelp: 'key',
      )
      ..addFlag(
        noLinkArgName,
        negatable: false,
        help:
            'Do not share a patch number with patches for other platforms, '
            'even when built from the same commit.',
      )
      ..addOption(
        CommonArguments.buildNameArg.name,
        help: CommonArguments.buildNameArg.description,
        defaultsTo: CommonArguments.buildNameArg.defaultValue,
      )
      ..addOption(
        CommonArguments.buildNumberArg.name,
        help: CommonArguments.buildNumberArg.description,
        defaultsTo: CommonArguments.buildNumberArg.defaultValue,
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: '''
The version of the associated release (e.g. "1.0.0").
If you are building an xcframework or aar, this number needs to match the host app's release version.
To target the latest release (e.g. the release that was most recently updated) use --release-version=latest.''',
      )
      ..addFlag(
        'allow-native-diffs',
        help: allowNativeDiffsHelpText,
        negatable: false,
      )
      ..addFlag(
        'allow-asset-diffs',
        help: allowAssetDiffsHelpText,
        negatable: false,
      )
      ..addFlag(
        'allow-build-flag-diffs',
        help: allowBuildFlagDiffsHelpText,
        negatable: false,
      )
      ..addFlag(
        'show-dex-diff',
        help: showDexDiffHelpText,
        negatable: false,
      )
      ..addOption(
        'track',
        aliases: const ['channel'],
        help:
            'The track to publish the patch to (staging, beta, stable, or a '
            'custom track). Asked for when not given.',
      )
      ..addOption(
        addToPatchArgName,
        valueHelp: 'number',
        help:
            "Add this machine's Windows build to an existing patch instead "
            'of creating a new one. Flutter builds Windows apps for the '
            'machine it runs on, so an app shipped for x64 and arm64 is '
            'patched on each kind of machine: patch on one, then add to that '
            'patch on the other, and the fix is one patch number on both. '
            'Build from the same code as the patch. The patch keeps its '
            'track and rollout. A patch on a protected track, or waiting for '
            'approval, cannot be added to: add to it on staging, then '
            'promote it.',
      )
      ..addOption(
        rolloutArgName,
        help: rolloutHelp('the patch'),
        valueHelp: 'percentage',
      )
      ..addOption(
        rolloutStepsArgName,
        help: rolloutStepsHelp('the patch'),
        valueHelp: 'steps',
      )
      ..addFlag(
        pauseWeekendsArgName,
        help: pauseWeekendsHelp,
        negatable: false,
      )
      ..addOption(
        timezoneArgName,
        help: timezoneHelp,
        valueHelp: 'name',
      )
      ..addFlag(
        'staging',
        negatable: false,
        help: '''
[DEPRECATED] Whether to publish the patch to the staging environment. Use --track=staging instead.''',
        hide: true,
      )
      ..addFlag(
        CommonArguments.noConfirmArg.name,
        help: CommonArguments.noConfirmArg.description,
        negatable: false,
        hide: true,
      )
      ..addOption(
        CommonArguments.exportOptionsPlistArg.name,
        help: CommonArguments.exportOptionsPlistArg.description,
      )
      ..addOption(
        CommonArguments.exportMethodArg.name,
        allowed: ExportMethod.values.map((e) => e.argName),
        help: CommonArguments.exportMethodArg.description,
        allowedHelp: {
          for (final method in ExportMethod.values)
            method.argName: method.description,
        },
      )
      ..addFlag(
        'codesign',
        help: 'Codesign the app bundle or XCFrameworks (iOS only).',
        defaultsTo: true,
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Validate but do not upload the patch.',
      )
      ..addOption(
        CommonArguments.privateKeyArg.name,
        help: CommonArguments.privateKeyArg.description,
      )
      ..addOption(
        CommonArguments.publicKeyArg.name,
        help: CommonArguments.publicKeyArg.description,
      )
      ..addOption(
        CommonArguments.publicKeyCmd.name,
        help: CommonArguments.publicKeyCmd.description,
      )
      ..addOption(
        CommonArguments.signCmd.name,
        help: CommonArguments.signCmd.description,
      )
      ..addOption(
        CommonArguments.splitDebugInfoArg.name,
        help: CommonArguments.splitDebugInfoArg.description,
      )
      ..addFlag(
        CommonArguments.obfuscateArg.name,
        help: CommonArguments.obfuscateArg.description,
        negatable: false,
        hide: true,
      )
      ..addOption(
        CommonArguments.minLinkPercentage.name,
        help: CommonArguments.minLinkPercentage.description,
        defaultsTo: CommonArguments.minLinkPercentage.defaultValue,
      )
      ..addFlag(
        'share-debug-info',
        negatable: false,
        help:
            "Share this patch's debugging information "
            '(build/patch-debug.zip, written when patching iOS or macOS) '
            "with Shorebird, whatever your organization's setting.",
      )
      ..addOption(
        CommonArguments.ddMaxBytesArg.name,
        hide: true,
        help: CommonArguments.ddMaxBytesArg.description,
      )
      ..addFlutterBuildOptions();
  }

  /// Warning message for when native code diffs are detected.
  static final allowNativeDiffsHelpText = '''
Patch even if native code diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Native code changes cannot be included in a patch and attempting to do so can cause your app to crash or behave unexpectedly.''';

  /// Help text for the full DEX diff flag.
  static const showDexDiffHelpText = '''
Print every differing instruction when native changes are detected in an Android patch.
Without this, the first few differing instructions of the first ten changed methods are shown, string constants are replaced by their length, and a payload such as a switch table or an array initializer is cut after its first few units. Output contains your app's bytecode, including class and method names, and is written to the shorebird.log file support asks you to attach.''';

  /// Warning message for when asset diffs are detected.
  static final allowAssetDiffsHelpText = '''
Patch even if asset diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Asset changes cannot be included in a patch can cause your app to behave unexpectedly.''';

  /// Help text for the flag to patch despite build flag diffs.
  static final allowBuildFlagDiffsHelpText = '''
Patch even if the --dart-define values or --target differ from the release's.
NOTE: this is ${styleBold.wrap('not')} recommended. A patch built with different values may fail to link or change code the release runs.''';

  /// The option naming an existing patch to add this build to.
  static const addToPatchArgName = 'add-to-patch';

  /// The options that set where and to whom a new patch is published, and
  /// what it links to, which a patch being added to already has.
  static const _publishArgNames = [
    'track',
    rolloutArgName,
    rolloutStepsArgName,
    pauseWeekendsArgName,
    timezoneArgName,
    patchKeyArgName,
    noLinkArgName,
  ];

  late final ResolvePatcher _resolvePatcher;

  /// The number of the existing patch to add this build to (--add-to-patch),
  /// or null to create a new patch. [run] rejects a value that isn't a
  /// positive integer.
  int? get addToPatchNumber => switch (results[addToPatchArgName]) {
    final String value => int.tryParse(value),
    _ => null,
  };

  /// The patch this build is added to, once [createPatch] has found it.
  ReleasePatch? _patchToAddTo;

  // Installs the Flutter it builds with (see ShorebirdFlutter.installRevision).
  @override
  bool get usesPinnedFlutter => false;

  /// The option that sets the key linking this patch to other platforms'.
  static const patchKeyArgName = 'patch-key';

  /// The flag that turns linking off.
  static const noLinkArgName = 'no-link';

  /// The longest key the server accepts.
  static const patchKeyMaxLength = 255;

  /// How this run links its platforms' patches, set by [run] before any
  /// platform is built.
  PatchLinkPlan _link = PatchLinkPlan.none;

  /// The patches of each release this run checks for already published
  /// platforms, by release id, fetched once per release.
  final _releasePatches = <int, Future<List<ReleasePatch>>>{};

  @override
  String get description =>
      'Creates a shorebird patch for the provided target platforms.';

  @override
  String get name => 'patch';

  @override
  String get usageFooter => flutterBuildOptionsUsage('patch');

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The build flavor, if provided.
  late String? flavor = results.findOption('flavor', argParser: argParser);

  /// The target script, if provided.
  late final String? target = resolveTarget();

  /// Whether to allow changes in assets (--allow-asset-diffs).
  bool get allowAssetDiffs => results['allow-asset-diffs'] == true;

  /// Whether to patch despite build flags that differ from the release's
  /// (--allow-build-flag-diffs).
  bool get allowBuildFlagDiffs => results['allow-build-flag-diffs'] == true;

  /// Whether to allow changes in native code (--allow-native-diffs).
  bool get allowNativeDiffs => results['allow-native-diffs'] == true;

  /// Whether the patch is targeting the latest release version
  /// (--release-version=latest).
  bool get useLatestRelease => results['release-version'] == 'latest';

  /// The deployment track to publish the patch to.
  DeploymentTrack get track => _track ??= _resolveTrack();
  DeploymentTrack? _track;

  /// Whether [track] is stable only because --track wasn't given and the CLI
  /// couldn't ask.
  bool _usedDefaultTrack = false;

  /// The track from --track, or asked for when it wasn't given.
  ///
  /// Without a terminal to ask in, a missing --track still means stable so CI
  /// scripts written against that default keep working, with a warning that
  /// a future release will require --track.
  DeploymentTrack _resolveTrack() {
    if (results['track'] case final String trackName) {
      // A new track is created on first publish, so reject a name that
      // `channels create` and `patches set-track` would also reject.
      final trackNameError = CommonArguments.nameError(
        label: 'Track name',
        value: trackName,
        maxLength: CommonArguments.trackNameMaxLength,
      );
      if (trackNameError != null) usageException(trackNameError);
      return DeploymentTrack(trackName);
    }

    if (shorebirdEnv.canAcceptUserInput) {
      return logger.chooseOne<DeploymentTrack>(
        'Which track should this patch be published to?',
        choices: const [
          DeploymentTrack.staging,
          DeploymentTrack.beta,
          DeploymentTrack.stable,
        ],
        defaultValue: DeploymentTrack.staging,
        display: (track) => track.channel,
      );
    }

    logger.warn(
      'No --track given, so this patch is published to the stable track, '
      'which reaches all users. A future release will require --track when '
      'it cannot ask. Pass --track=stable to keep publishing to stable, or '
      '--track=staging to test the patch before promoting it.',
    );
    _usedDefaultTrack = true;
    return DeploymentTrack.stable;
  }

  /// The share of [track]'s devices to publish the patch to (`--rollout`), or
  /// null for all of them. [run] rejects a value that does not parse.
  /// When adding to a patch, its current share instead.
  double? get rolloutPercentage {
    if (_patchToAddTo case final patch?) return patch.rolloutPercentage;
    return switch (results[rolloutArgName]) {
      final String value => parseRolloutPercentage(
        value,
        argName: rolloutArgName,
      ).percentage,
      _ => null,
    };
  }

  /// The timed schedule to raise the patch's rollout through
  /// (`--rollout-steps`), or null when the patch is published at a fixed
  /// percentage. [run] rejects a schedule that does not parse.
  /// When adding to a patch, its schedule instead, if it has one.
  RolloutSchedule? get rolloutSchedule {
    if (_patchToAddTo case final patch?) {
      return switch (patch.rolloutSteps) {
        final steps? when steps.isNotEmpty => RolloutSchedule(
          steps: steps,
          pauseWeekends: patch.rolloutPauseWeekends ?? false,
          timezone: patch.rolloutTimezone,
        ),
        _ => null,
      };
    }
    return readRolloutSchedule(
      results,
      percentageArgName: rolloutArgName,
    ).schedule;
  }

  @override
  Future<int> run() async {
    final releaseTypes = releaseTypesOrUsageError(siblingCommand: 'patches');

    final ddMaxBytes = results[CommonArguments.ddMaxBytesArg.name] as String?;
    if (ddMaxBytes != null && (int.tryParse(ddMaxBytes) ?? -1) < 0) {
      usageException(
        '--${CommonArguments.ddMaxBytesArg.name} must be a non-negative '
        'integer (got $ddMaxBytes).',
      );
    }

    // Checked before anything is built or created, so a typo costs nothing.
    if (results[rolloutArgName] case final String rollout) {
      final error = parseRolloutPercentage(
        rollout,
        argName: rolloutArgName,
      ).error;
      if (error != null) usageException(error);
    }
    final scheduleError = readRolloutSchedule(
      results,
      percentageArgName: rolloutArgName,
    ).error;
    if (scheduleError != null) usageException(scheduleError);

    if (results[addToPatchArgName] case final String value) {
      _assertCanAddToPatch(value: value, releaseTypes: releaseTypes);
    }

    if (results.wasParsed('staging')) {
      return reportError(
        message: '--staging is no longer supported.',
        hint: 'Pass --track=staging instead.',
      );
    }

    final patchKey = (results[patchKeyArgName] as String?)?.trim();
    final noLink = results[noLinkArgName] == true;
    if (patchKey != null) {
      if (patchKey.isEmpty) {
        usageException('--$patchKeyArgName cannot be empty.');
      }
      if (patchKey.length > patchKeyMaxLength) {
        usageException(
          '--$patchKeyArgName must be at most $patchKeyMaxLength characters '
          '(got ${patchKey.length}).',
        );
      }
      if (noLink) {
        usageException(
          'Pass --$patchKeyArgName or --$noLinkArgName, not both.',
        );
      }
    }

    final patchers = [
      for (final releaseType in releaseTypes) _resolvePatcher(releaseType),
    ];
    // Check every platform before building any, so a platform this machine
    // can't patch stops the run before another platform's patch is published.
    for (final patcher in patchers) {
      await _assertCanPatch(patcher);
    }

    // Decided once, so every platform built by this run sends the same key.
    // A build added to an existing patch joins that patch, so it has no key.
    _link = addToPatchNumber != null
        ? PatchLinkPlan.none
        : await resolvePatchLink(
            patchKey: patchKey,
            noLink: noLink,
            platforms: [
              for (final p in patchers) p.releaseType.releasePlatform,
            ],
            projectRoot:
                shorebirdEnv.getShorebirdProjectRoot() ?? Directory.current,
          );

    final published = <PublishedPatch>[];
    for (final (index, patcher) in patchers.indexed) {
      try {
        published.add(await _recordPatchRun(patcher));
      } catch (_) {
        if (published.any((p) => !p.alreadyPublished)) {
          final unfinished = patchers.skip(index).toList();
          if (isJsonMode) {
            // A random key is not derived again on a rerun, so a script
            // needs it to finish the remaining platforms under one number.
            read(jsonEnvelopeTrackerRef, orElse: () => null)?.errorData = {
              'link_key': _link.key,
              'patches': [for (final p in published) p.toJson()],
              'unfinished_platforms': [
                for (final p in unfinished) p.releaseType.cliName,
              ],
            };
          } else {
            _logPublished(published);
            if (_link.source == PatchLinkSource.random) {
              _logResumeCommand(unfinished: unfinished);
            }
          }
        }
        rethrow;
      }
    }

    final schedule = rolloutSchedule;
    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'track': track.channel,
        'rollout_percentage':
            _patchToAddTo?.rolloutPercentage ??
            schedule?.initialPercentage ??
            rolloutPercentage ??
            100.0,
        if (schedule != null) ...{
          'rollout_steps': [for (final step in schedule.steps) step.toJson()],
          'rollout_pause_weekends': schedule.pauseWeekends,
          'rollout_timezone': ?schedule.timezone,
        },
        'link_key': _link.key,
        'patches': [for (final p in published) p.toJson()],
      });
      return ExitCode.success.code;
    }

    if (_patchToAddTo == null) _logPublished(published);
    // A skipped platform keeps the rollout an earlier run gave it.
    final newlyPublished = [
      for (final p in published)
        if (!p.alreadyPublished) p,
    ];
    if (schedule != null) {
      _logScheduledRollout(published: newlyPublished, schedule: schedule);
    } else if (rolloutPercentage case final percentage? when percentage < 100) {
      _logPartialRollout(published: newlyPublished, percentage: percentage);
    }

    return ExitCode.success.code;
  }

  /// Says which patch number each platform this run published in [published]
  /// has, one line for each number, and that platforms on different releases
  /// are not linked. Platforms an earlier run published are left out; they
  /// were reported when skipped.
  void _logPublished(List<PublishedPatch> published) {
    final newlyPublished = published.where((p) => !p.alreadyPublished);
    if (newlyPublished.isEmpty) {
      logger.info('\nNothing new to publish.');
      return;
    }
    final releaseVersions = {for (final p in published) p.release.version};
    final groups = <(String, int), List<ReleasePlatform>>{};
    for (final p in newlyPublished) {
      groups
          .putIfAbsent((p.release.version, p.patch.number), () => [])
          .add(p.platform);
    }
    final parts = [
      for (final MapEntry(key: (version, number), value: platforms)
          in groups.entries)
        [
          'patch $number',
          if (releaseVersions.length > 1) 'on release $version',
          '(${platforms.map((p) => p.displayName).join(', ')})',
        ].join(' '),
    ];
    logger.success('\n✅ Published ${parts.join(' and ')}!');

    if (_link.key != null && releaseVersions.length > 1) {
      final patched = [
        for (final p in published)
          '${p.platform.displayName} ${p.release.version}',
      ].join(', ');
      logger.info(
        'Not linked across releases: patches share a number only within one '
        'release, and these platforms patched different ones ($patched).',
      );
    }
  }

  /// Prints the command that publishes the [unfinished] platforms under this
  /// run's key, for a run whose key no rerun would derive again: this run's
  /// own arguments with the platforms and key replaced, quoted for a shell.
  void _logResumeCommand({required List<Patcher> unfinished}) {
    final args = [
      '--platforms=${unfinished.map((p) => p.releaseType.cliName).join(',')}',
      '--$patchKeyArgName=${_link.key}',
      ..._argumentsWithoutPlatformsOrKey(),
    ].map(shellQuote).join(' ');
    logger.info(
      'To give the remaining platforms the same patch number, run:\n'
      '  ${lightCyan.wrap('shorebird $name $args')}',
    );
  }

  /// This run's arguments without `--platforms` (`-p`) and `--patch-key`
  /// and their values. Arguments after `--` are kept as given.
  List<String> _argumentsWithoutPlatformsOrKey() {
    const names = ['platforms', patchKeyArgName];
    final args = results.arguments;
    final kept = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--') {
        kept.addAll(args.skip(i));
        break;
      }
      if (arg == '-p' || names.any((name) => arg == '--$name')) {
        i++; // Skips the value in the next argument.
        continue;
      }
      if ((arg.startsWith('-p') && !arg.startsWith('--')) ||
          names.any((name) => arg.startsWith('--$name='))) {
        continue;
      }
      kept.add(arg);
    }
    return kept;
  }

  /// Says what a rollout below 100% means for each of [published] and how to
  /// raise it.
  void _logPartialRollout({
    required List<PublishedPatch> published,
    required double percentage,
  }) {
    final share = formatRolloutPercentage(percentage);
    for (final p in published) {
      final releaseVersion = p.release.version;
      final patchNumber = p.patch.number;
      final raiseCommand = raiseRolloutCommand(
        releaseVersion: releaseVersion,
        patchNumber: patchNumber,
        flavor: flavor,
      );
      logger.info(
        'Patch $patchNumber on release $releaseVersion is rolling out to '
        '$share of devices on ${track.channel}. To raise it, run:\n'
        '  ${lightCyan.wrap(raiseCommand)}',
      );
    }
    logger.info(rolloutOlderDevicesNote);
  }

  /// Says what schedule each of [published] is rolling out on and how to
  /// raise it sooner.
  void _logScheduledRollout({
    required List<PublishedPatch> published,
    required RolloutSchedule schedule,
  }) {
    for (final p in published) {
      final releaseVersion = p.release.version;
      final patchNumber = p.patch.number;
      final raiseCommand = raiseRolloutCommand(
        releaseVersion: releaseVersion,
        patchNumber: patchNumber,
        flavor: flavor,
      );
      logger.info(
        'Patch $patchNumber on release $releaseVersion is rolling out to '
        '${track.channel} on a schedule: ${formatRolloutSchedule(schedule)}. '
        'To raise it sooner, run:\n'
        '  ${lightCyan.wrap(raiseCommand)}',
      );
    }
    logger.info(rolloutOlderDevicesNote);
  }

  /// Returns a [Patcher] for the given [ReleaseType].
  @visibleForTesting
  Patcher getPatcher(ReleaseType releaseType) {
    switch (releaseType) {
      case ReleaseType.aar:
        return AarPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.android:
        return AndroidPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.ios:
        return IosPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.iosFramework:
        return IosFrameworkPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.linux:
        return LinuxPatcher(
          argParser: argParser,
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.macos:
        return MacosPatcher(
          argParser: argParser,
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.windows:
        return WindowsPatcher(
          argResults: results,
          argParser: argParser,
          flavor: flavor,
          target: target,
        );
    }
  }

  /// The build history record of the platform being patched, if [run] is
  /// patching.
  BuildRun? _buildRun;

  /// Whether the release being patched was guessed by building the app.
  bool _inferredReleaseVersion = false;

  /// What the diff check found, once it has run.
  DiffStatus? _diffStatus;

  /// [shorebirdEnv] with the Flutter of the release being patched, once it
  /// is known.
  ShorebirdEnv? _releaseShorebirdEnv;

  /// Creates the patch for [patcher] with [createPatch], recording the run in
  /// the app's build history.
  Future<PublishedPatch> _recordPatchRun(Patcher patcher) {
    _inferredReleaseVersion = false;
    _diffStatus = null;
    _releaseShorebirdEnv = null;
    final run = _buildRun =
        buildHistory.start(
            command: BuildRunCommand.patch,
            platform: patcher.releaseType.releasePlatform,
            dryRun: results['dry-run'] == true,
          )
          ..shareDebugInfo = results['share-debug-info'] == true
          ..watchDebugBundle(Patcher.debugInfoFile);
    return buildHistory.record(
      run,
      () => createPatch(patcher),
      // Described with the release's Flutter, as the published patch is.
      metadata: () => runScoped(
        () async => (await _createPatchMetadata(
          patcher: patcher,
          diffStatus:
              _diffStatus ??
              const DiffStatus(hasAssetChanges: false, hasNativeChanges: false),
          inferredReleaseVersion: _inferredReleaseVersion,
        )).toJson(),
        values: {
          if (_releaseShorebirdEnv case final env?)
            shorebirdEnvRef.overrideWith(() => env),
        },
      ),
    );
  }

  /// Creates a patch using the provided [patcher].
  ///
  /// Returns what was published. A dry run does not return: it exits the
  /// process with success once the patch has been checked.
  @visibleForTesting
  Future<PublishedPatch> createPatch(Patcher patcher) async {
    await _assertCanPatch(patcher);

    // Artifacts are updated once the release's Flutter is in scope
    // (_buildAndPublishPatch): they are per engine revision, and the
    // pinned one's would go unused when the release used another Flutter.

    final app = await codePushClientWrapper.getApp(appId: appId);
    patcher.crashReportingEnabled = app.crashReportingEnabled;

    final resolved = await _resolveRelease(patcher);
    final release = resolved.release;
    _inferredReleaseVersion = resolved.inferredReleaseVersion;
    final releaseFlutterShorebirdEnv = _releaseShorebirdEnv = shorebirdEnv
        .copyWith(flutterRevisionOverride: release.flutterRevision);
    _buildRun
      ?..appId = appId
      ..releaseId = release.id
      ..buildFlags = buildHistory.buildFlags(results, target: patcher.target);

    assertReleaseContainsPlatform(release: release, patcher: patcher);
    assertReleaseIsActive(release: release, patcher: patcher);

    if (await _findPublishedUnderKey(patcher: patcher, release: release)
        case final existing?) {
      logger.info(
        '${patcher.releaseType.releasePlatform.displayName} already '
        'published as patch ${existing.number}.',
      );
      return PublishedPatch(
        platform: patcher.releaseType.releasePlatform,
        release: release,
        patch: CreatePatchResponse(id: existing.id, number: existing.number),
        linkPercentage: null,
        alreadyPublished: true,
      );
    }
    _assertCanSignForRelease(release: release, patcher: patcher);
    _assertReleaseSignedForPolicy(app: app, release: release, patcher: patcher);
    _warnIfFlutterRevisionHasKnownIssue(release: release, patcher: patcher);
    if (addToPatchNumber case final patchNumber?) {
      final patch = _patchToAddTo = await _findPatchToAddTo(
        patcher: patcher,
        release: release,
        patchNumber: patchNumber,
      );
      _track = DeploymentTrack(patch.channel!);
    }

    try {
      await shorebirdFlutter.installRevision(revision: release.flutterRevision);
    } on Exception {
      throw ProcessExit(ExitCode.software.code);
    }

    // Fail before downloading anything if the release's Flutter is too old.
    await runScoped(
      () async {
        await _assertReleaseFlutterVersionSupported(
          patcher: patcher,
          release: release,
        );
        await _warnIfInstallOnlySkipsSignatureCheck(release: release);
      },
      values: {shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv)},
    );

    await patcher.prepareForRelease(appId: appId, release: release);
    final downloaded = await _downloadReleaseArtifacts(
      patcher: patcher,
      release: release,
    );
    _configureSigning(
      patcher: patcher,
      release: release,
      releaseArtifact: downloaded.releaseArtifact,
    );

    // The extracted supplement (including any obfuscation map the build loads)
    // is needed until the patch is built and published.
    try {
      await _configureObfuscation(
        patcher: patcher,
        release: release,
        obfuscationMapFile: downloaded.obfuscationMapFile,
      );
      _assertBuildFlagsMatchRelease(
        patcher: patcher,
        release: release,
        supplementDirectory: downloaded.supplementDirectory,
      );

      return await runScoped(
        () => _buildAndPublishPatch(
          patcher: patcher,
          app: app,
          release: release,
          inferredReleaseVersion: resolved.inferredReleaseVersion,
          releaseArtifact: downloaded.releaseArtifact,
          releaseArchive: downloaded.releaseArchive,
          supplementDirectory: downloaded.supplementDirectory,
        ),
        values: {
          shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
        },
      );
    } finally {
      if (downloaded.supplementDirectory case final directory?) {
        directory.deleteTemporarySync();
      }
    }
  }

  /// Returns [patcher]'s platform's patch on [release] that an earlier run
  /// published under this run's key, which is this commit's SHA, to
  /// [track], or null when this run should build and publish it.
  ///
  /// Only the platform's newest patch on the release counts, so a platform
  /// that has moved on to a newer patch is published again, and only once
  /// its artifacts are uploaded and while it is not rolled back. Skipped on a
  /// dirty tree or a dry run, where the commit does not prove the build
  /// would be the same.
  Future<ReleasePatch?> _findPublishedUnderKey({
    required Patcher patcher,
    required Release release,
  }) async {
    final key = _link.key;
    if (key == null || !_link.canSkipPublished) return null;
    if (results['dry-run'] == true) return null;

    // The whole list, not only the key's patches, to see whether the
    // platform has a newer patch than the one under the key.
    final patches = await _releasePatches.putIfAbsent(
      release.id,
      () => codePushClientWrapper.getReleasePatches(
        appId: appId,
        releaseId: release.id,
      ),
    );
    final platform = patcher.releaseType.releasePlatform;
    final platformPatches = patches
        .where((p) => p.resolvedPlatform == platform)
        .toList();
    if (platformPatches.isEmpty) return null;
    final newest = platformPatches.map((p) => p.number).max;
    return platformPatches.firstWhereOrNull(
      (p) =>
          p.number == newest &&
          p.linkKey == key &&
          p.artifacts.isNotEmpty &&
          !p.isRolledBack &&
          p.channel == track.channel,
    );
  }

  /// The patchers [_assertCanPatch] has already passed.
  final _checkedPatchers = Set<Patcher>.identity();

  /// Checks that [patcher] can build a patch with the given arguments and
  /// flavors, exiting otherwise. A patcher already checked is not checked
  /// again.
  Future<void> _assertCanPatch(Patcher patcher) async {
    if (_checkedPatchers.contains(patcher)) return;
    await patcher.assertPreconditions();
    await patcher.assertArgsAreValid();
    assertSigningArgsValid();

    // Resolve the track now so a bad --track, or the prompt for a missing
    // one, comes before the build rather than after it. A dry run publishes
    // nothing, so it only checks a --track that was given.
    // A patch being added to keeps the track it is on.
    if (addToPatchNumber == null &&
        (results['dry-run'] != true || results['track'] != null)) {
      _track ??= _resolveTrack();
    }

    try {
      await shorebirdValidator.validateFlavors(
        flavorArg: flavor,
        releasePlatform: patcher.releaseType.releasePlatform,
      );
    } on ValidationFailedException catch (e) {
      throw PreconditionFailedExit(e);
    }
    _checkedPatchers.add(patcher);
  }

  /// Rejects --add-to-patch=[value] unless it names a patch number and the
  /// run patches Windows alone with no track or rollout of its own.
  void _assertCanAddToPatch({
    required String value,
    required Iterable<ReleaseType> releaseTypes,
  }) {
    final number = int.tryParse(value);
    if (number == null || number < 1) {
      usageException(
        '--$addToPatchArgName must be a patch number (got "$value").',
      );
    }
    if (releaseTypes.length != 1 ||
        releaseTypes.single != ReleaseType.windows) {
      usageException(
        '--$addToPatchArgName only works with `shorebird patch windows`. '
        'Other platforms build every architecture into one patch.',
      );
    }
    final publishArgs = _publishArgNames.where(results.wasParsed);
    if (publishArgs.isNotEmpty) {
      usageException(
        'Patch $number keeps its own track, rollout and link. Remove '
        '${publishArgs.map((arg) => '--$arg').join(', ')}.',
      );
    }
  }

  /// Finds patch [patchNumber] of [release] and checks that [patcher]'s build
  /// can be added to it: it is live, on a track, and has a build for this
  /// platform but not for this machine's architecture.
  Future<ReleasePatch> _findPatchToAddTo({
    required Patcher patcher,
    required Release release,
    required int patchNumber,
  }) async {
    final patches = await codePushClientWrapper.getReleasePatches(
      appId: appId,
      releaseId: release.id,
    );
    final platform = patcher.releaseType.releasePlatform;
    const createPatchHint =
        'To ship this build as a new patch, run without '
        '--$addToPatchArgName.';
    Never fail(String message, {String? hint}) {
      _buildRun?.failWith(BuildRunFailureReason.releaseIncompatible);
      throw CommandError(
        message: message,
        hint: hint ?? createPatchHint,
      );
    }

    final patch = patches.firstWhereOrNull((p) => p.number == patchNumber);
    final name = 'Patch $patchNumber of release ${release.version}';
    if (patch == null) {
      fail(
        'Release ${release.version} has no patch $patchNumber.',
        hint: patches.isEmpty
            ? createPatchHint
            : 'Its patches: ${patches.map((p) => p.number).join(', ')}.',
      );
    }
    if (patch.isRolledBack) fail('$name is rolled back.');
    final channel = patch.channel;
    if (channel == null) {
      fail(
        '$name is not on a track.',
        hint:
            'A patch waiting for approval cannot be added to. '
            '$createPatchHint',
      );
    }
    final platformArches = [
      for (final artifact in patch.artifacts)
        if (artifact.platform == platform) artifact.arch,
    ];
    if (platformArches.isEmpty) {
      fail('$name has no ${platform.displayName} build to add to.');
    }
    if (patcher.patchArch case final arch?
        when platformArches.contains(arch.arch)) {
      fail(
        '$name already has a ${platform.displayName} ${arch.name} build.',
        hint:
            'Add to it from a machine of another architecture, or run '
            'without --$addToPatchArgName to ship this build as a new patch.',
      );
    }
    // Devices take the newest live patch on their track with a build for
    // their architecture, so a newer one would leave this build unused.
    if (patcher.patchArch case final arch?) {
      final newer = patches.where(
        (p) =>
            p.number > patchNumber &&
            !p.isRolledBack &&
            p.channel == channel &&
            p.artifacts.any(
              (a) => a.platform == platform && a.arch == arch.arch,
            ),
      );
      if (newer.isNotEmpty) {
        final newest = newer.map((p) => p.number).max;
        fail(
          '${platform.displayName} ${arch.name} devices on $channel take '
          'patch $newest of release ${release.version}, which is newer than '
          'patch $patchNumber, so they would never get this build.',
          hint: 'Patch $newest already has their build. $createPatchHint',
        );
      }
    }
    return patch;
  }

  /// Determines which release to patch.
  ///
  /// When the release version can't be determined any other way, the app is
  /// built once to read the version from it. That build is only for the
  /// version: the patch is built again with the release's settings.
  Future<({Release release, bool inferredReleaseVersion})> _resolveRelease(
    Patcher patcher,
  ) async {
    var inferredReleaseVersion = false;
    final Release release;
    final releasePlatform = patcher.releaseType.releasePlatform;
    if (useLatestRelease) {
      final releases = await codePushClientWrapper.getReleases(appId: appId);
      releases
        ..removeWhere(
          (release) => !release.hasPlatform(releasePlatform),
        )
        ..sortByUpdatedAt();
      if (releases.isEmpty) {
        throw _noReleasesToPatch(patcher.releaseType);
      }
      // Use the most recently updated release for the specified platform.
      release = releases.last;
    } else if (results.wasParsed('release-version')) {
      final releaseVersion = results['release-version'] as String;
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    } else if (shorebirdEnv.canAcceptUserInput) {
      release = await promptForRelease(patcher.releaseType);
    } else {
      // Without a terminal to prompt in, the release version is guessed by
      // building and reading it back out of the artifact, which some release
      // types can't do.
      if (patcher.requiresReleaseVersionArg) {
        usageException(
          'Missing required argument: --release-version. The release version '
          "can't be determined from a ${patcher.releaseType.cliName} build, "
          'so pass --release-version=<version> (or --release-version=latest) '
          'when running non-interactively.',
        );
      }
      // The guessing build uses the pinned Flutter, which nothing has
      // installed yet (see ShorebirdCommand.usesPinnedFlutter).
      final pinnedRevision = shorebirdEnv.flutterRevision;
      if (!shorebirdFlutter.isInstalled(revision: pinnedRevision)) {
        try {
          await shorebirdFlutter.installRevision(revision: pinnedRevision);
        } on Exception {
          throw ProcessExit(ExitCode.software.code);
        }
      }
      final flutterVersionString = await shorebirdFlutter
          .getVersionAndRevision();
      logger.warn(
        'Guessing the release version is deprecated and will be removed in '
        'a release after 2027-01-01. Pass --release-version=<version> (or '
        '--release-version=latest for the most recently updated release). '
        'Without it, shorebird builds your app an extra time with Flutter '
        '$flutterVersionString to guess which release to patch, which is '
        'slower and less accurate. See '
        'https://github.com/shorebirdtech/shorebird/issues/4354',
      );
      inferredReleaseVersion = true;
      final versionArtifact = await _tryBuildingArtifact<File>(
        patcher.buildPatchArtifact,
      );
      final releaseVersion = await patcher.extractReleaseVersionFromArtifact(
        versionArtifact,
      );
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    }

    return (
      release: release,
      inferredReleaseVersion: inferredReleaseVersion,
    );
  }

  /// Downloads [release]'s primary artifact and, if the platform has one, its
  /// supplement, which is extracted. Detects whether the release was built
  /// with obfuscation from the supplement's obfuscation map.
  Future<
    ({
      ReleaseArtifact releaseArtifact,
      File releaseArchive,
      Directory? supplementDirectory,
      File? obfuscationMapFile,
    })
  >
  _downloadReleaseArtifacts({
    required Patcher patcher,
    required Release release,
  }) async {
    final releasePlatform = patcher.releaseType.releasePlatform;
    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: patcher.primaryReleaseArtifactArch,
      platform: releasePlatform,
    );

    final supplementalArtifact =
        patcher.supplementaryReleaseArtifactArch != null
        ? await codePushClientWrapper.maybeGetReleaseArtifact(
            appId: appId,
            releaseId: release.id,
            arch: patcher.supplementaryReleaseArtifactArch!,
            platform: releasePlatform,
          )
        : null;

    final releaseArchive = await downloadReleaseArtifact(
      releaseArtifact: releaseArtifact,
    );

    final supplementArchive = supplementalArtifact != null
        ? await downloadReleaseArtifact(releaseArtifact: supplementalArtifact)
        : null;

    // Download and extract the supplement archive (if present).
    Directory? supplementDirectory;
    File? obfuscationMapFile;
    if (supplementArchive != null) {
      supplementDirectory = Directory.systemTemp.createTempSync();
      await extractReleaseArtifact(
        zipFile: supplementArchive,
        outputDirectory: supplementDirectory,
        releaseType: patcher.releaseType,
      );
      final candidateMapFile = File(
        p.join(supplementDirectory.path, 'obfuscation_map.json'),
      );
      if (candidateMapFile.existsSync()) {
        obfuscationMapFile = candidateMapFile;
        logger.info(
          'Release was built with obfuscation. '
          'Applying obfuscation map to patch build.',
        );
      }
    }

    return (
      releaseArtifact: releaseArtifact,
      releaseArchive: releaseArchive,
      supplementDirectory: supplementDirectory,
      obfuscationMapFile: obfuscationMapFile,
    );
  }

  /// Configures [patcher] to build the patch against the key [release]'s
  /// [releaseArtifact] embeds.
  ///
  /// Shorebird signs the patches of a release that embeds a managed key, so
  /// passing a key of your own for one is a usage error.
  void _configureSigning({
    required Patcher patcher,
    required Release release,
    required ReleaseArtifact releaseArtifact,
  }) {
    final signing = releaseArtifact.signing;
    if (signing?.mode != ReleaseSigningMode.managed.value) return;

    final keyArgs = [
      CommonArguments.publicKeyArg.name,
      CommonArguments.publicKeyCmd.name,
      CommonArguments.privateKeyArg.name,
      CommonArguments.signCmd.name,
    ].where(results.wasParsed);
    if (keyArgs.isNotEmpty) {
      usageException(
        'Release ${release.version} is signed with a Shorebird-managed key, '
        'and Shorebird signs its patches. Remove '
        '${keyArgs.map((arg) => '--$arg').join(', ')}.',
      );
    }
    final publicKeyPem = signing!.publicKeyPem;
    if (publicKeyPem == null) {
      throw CommandError(
        message:
            'Release ${release.version} is signed with a Shorebird-managed '
            'key, but the server did not return it.',
        hint: 'Try again, and contact Shorebird support if this persists.',
        exitCode: ExitCode.software,
      );
    }
    patcher.releaseManagedPublicKeyPem = publicKeyPem;
  }

  /// Stops before the patch build when its dart-defines or target differ
  /// from those [release] recorded in its supplement, which would fail to
  /// link or change code the release runs. With --allow-build-flag-diffs,
  /// or when the user confirms in a terminal, it goes on: a define the code
  /// never reads changes nothing. Releases from a
  /// CLI that recorded no flags aren't checked.
  void _assertBuildFlagsMatchRelease({
    required Patcher patcher,
    required Release release,
    required Directory? supplementDirectory,
  }) {
    if (supplementDirectory == null) return;
    final file = File(p.join(supplementDirectory.path, BuildFlags.fileName));
    if (!file.existsSync()) return;
    final releaseFlags = BuildFlags.tryParse(file.readAsStringSync());
    if (releaseFlags == null) {
      logger.detail(
        'Not checking build flags: ${BuildFlags.fileName} is '
        'from a newer CLI or unreadable.',
      );
      return;
    }
    final BuildFlags patchFlags;
    try {
      patchFlags = BuildFlags.fromArgs(results, target: patcher.target);
    } on FormatException catch (error) {
      usageException(error.message);
    }
    final differences = patchFlags.differencesFrom(releaseFlags);
    if (differences.isEmpty) return;

    final platform = patcher.releaseType.releasePlatform.displayName;
    logger.warn(
      '''
This patch isn't built with the same flags as release ${release.version} ($platform):
${differences.map((line) => '  $line').join('\n')}
A patch must be built with the --dart-define values and --target of its release, or it may fail to link or change code the release runs.''',
    );
    if (allowBuildFlagDiffs) return;
    if (!shorebirdEnv.canAcceptUserInput) {
      _buildRun?.failWith(BuildRunFailureReason.buildFlagDiffs);
      throw CommandError(
        message: "This patch's flags don't match release ${release.version}.",
        hint:
            'Pass the same --dart-define, --dart-define-from-file and '
            '--target values as the release, or create a new release. To '
            'patch anyway, pass --allow-build-flag-diffs.',
        code: JsonErrorCode.interactivePromptRequired,
      );
    }
    if (logger.confirm('Continue anyway?')) return;
    logger.err('Aborting.');
    _buildRun?.failWith(BuildRunFailureReason.buildFlagDiffs);
    throw PromptDeclinedExit();
  }

  /// Configures [patcher] to build the patch with the same obfuscation as
  /// [release], which has [obfuscationMapFile] if it was obfuscated, and sets
  /// the extra Flutter build args that requires.
  Future<void> _configureObfuscation({
    required Patcher patcher,
    required Release release,
    required File? obfuscationMapFile,
  }) async {
    final releasePlatform = patcher.releaseType.releasePlatform;

    // If the user explicitly passed --obfuscate but the release has no
    // obfuscation map, the patch would be obfuscated against a non-obfuscated
    // release, producing a broken patch.
    final userPassedObfuscate = results.flagPresent('obfuscate');
    if (userPassedObfuscate && obfuscationMapFile == null) {
      usageException(
        '--obfuscate was passed, but release ${release.version} was not '
        'built with obfuscation. A patch cannot change the obfuscation mode '
        'of a release: re-run without --obfuscate to patch this release, or '
        'create a new release with --obfuscate.',
      );
    }
    if (userPassedObfuscate && obfuscationMapFile != null) {
      logger.info(
        '--obfuscate is not needed for patching. Obfuscation is applied '
        'automatically when the release was built with --obfuscate.',
      );
    }

    // Building a patch with the release's obfuscated names needs
    // gen_snapshot's --load-obfuscation-map, which older Flutter versions
    // lack. Only patches that are linked against the release need matching
    // names; elsewhere the patch is obfuscated independently instead.
    var loadObfuscationMap = obfuscationMapFile != null;
    final releaseFlutterVersion = tryParseVersion(release.flutterVersion ?? '');
    if (loadObfuscationMap &&
        releaseFlutterVersion != null &&
        !releaseFlutterVersion.satisfiesFloor(
          minimumObfuscationFlutterVersion,
        )) {
      if (patchesLinkAgainstRelease(releasePlatform)) {
        _buildRun?.failWith(BuildRunFailureReason.releaseIncompatible);
        throw CommandError(
          message:
              'Release ${release.version} was built with obfuscation on '
              'Flutter $releaseFlutterVersion, but patching an obfuscated '
              '${releasePlatform.displayName} release requires Flutter '
              '$minimumObfuscationFlutterVersion or later.',
          hint:
              'Create a new release to patch. Run: '
              '${patcher.releaseType.releaseCommand()} --obfuscate '
              '--flutter-version=$minimumObfuscationFlutterVersion',
          exitCode: ExitCode.unavailable,
        );
      }
      loadObfuscationMap = false;
    }

    patcher
      ..obfuscate = obfuscationMapFile != null
      ..obfuscationMapPath = loadObfuscationMap
          ? obfuscationMapFile!.path
          : null;

    // Build extra args to inject into the Flutter build command. These use
    // --extra-gen-snapshot-options= because they're passed through Flutter's
    // build system, which forwards them to gen_snapshot. This is distinct from
    // patcher.obfuscationGenSnapshotArgs, which produces bare gen_snapshot
    // flags (e.g. --load-obfuscation-map=...) for direct gen_snapshot/linker
    // calls made by Apple patchers outside the Flutter build.
    final extraBuildArgs = <String>[];
    if (obfuscationMapFile != null) {
      extraBuildArgs.add('--obfuscate');
      if (loadObfuscationMap) {
        final loadMapOption =
            '--load-obfuscation-map=${obfuscationMapFile.path}';
        extraBuildArgs.add('--extra-gen-snapshot-options=$loadMapOption');
      }

      // Gate --strip on the release's Flutter revision (not the user's
      // currently-installed pin) so the patch's gen_snapshot behavior
      // matches the release's. On Android with Flutter 3.44+ AGP performs
      // the strip; passing --strip here would pre-strip the snapshot,
      // leaving AGP nothing to strip and tripping flutter_tools'
      // post-build "libapp.so.sym or libapp.so.dbg not present" check.
      final shouldPreStripInGenSnapshot = await shorebirdFlutter
          .shouldPreStripLibappInGenSnapshot(
            platform: patcher.releaseType.releasePlatform,
            flutterRevision: release.flutterRevision,
          );

      if (shouldPreStripInGenSnapshot) {
        // Strip unobfuscated DWARF debug info from the compiled snapshot
        // so it doesn't leak identifiers that obfuscation was meant to
        // hide. On Android 3.44+ this is handled by AGP instead; see the
        // block above.
        extraBuildArgs.add('--extra-gen-snapshot-options=--strip');
      }
    }
    // --obfuscate may come from the user or from the obfuscation map
    // injection above; either way it needs --split-debug-info, as on release.
    final splitDebugInfo = splitDebugInfoDefault(
      obfuscate:
          results.flagPresent('obfuscate') ||
          extraBuildArgs.contains('--obfuscate'),
      hasSplitDebugInfo: results.optionPresent('split-debug-info'),
    );
    if (splitDebugInfo != null) extraBuildArgs.add(splitDebugInfo);
    patcher.extraBuildArgs = extraBuildArgs;
  }

  /// Builds the patch with [release]'s Flutter revision and settings, checks
  /// it against the release, and uploads it. Must run with the release's
  /// Flutter revision in scope.
  ///
  /// A dry run exits the process with success once the patch is checked.
  Future<PublishedPatch> _buildAndPublishPatch({
    required Patcher patcher,
    required AppMetadata app,
    required Release release,
    required bool inferredReleaseVersion,
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required Directory? supplementDirectory,
  }) async {
    await cache.updateAll();

    // Set up build tracing before any flutter build / aot_tools /
    // gen_snapshot call runs. Version-gated inside prepareBuildTrace —
    // a no-op on older Flutter pins. Summary is written before the upload
    // for the patch's metadata, and again after it for build history.
    await artifactBuilder.prepareBuildTrace(
      platform: patcher.releaseType.releasePlatform.name,
    );

    // Always build here, even if the app was built to guess the release
    // version: that build used the current Flutter and none of the release's
    // settings (obfuscation, a managed signing key).
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    logger.info('''
Building patch with Flutter $flutterVersionString
''');
    patcher.releaseSupplementDirectory = supplementDirectory;
    final patchArtifactFile = await _tryBuildingArtifact<File>(
      () => patcher.buildPatchArtifact(
        releaseVersion: release.version,
      ),
      onBuildFailed: () =>
          _buildRun?.failWith(BuildRunFailureReason.buildFailed),
    );

    final diffStatus = await assertUnpatchableDiffs(
      releaseArtifact: releaseArtifact,
      releaseArchive: releaseArchive,
      patchArchive: patchArtifactFile,
      patcher: patcher,
    );
    _diffStatus = diffStatus;
    final patchArtifactBundles = await blameFailureOn(
      _buildRun,
      BuildRunFailureReason.buildFailed,
      () => patcher.createPatchArtifacts(
        appId: appId,
        releaseId: release.id,
        releaseArtifact: releaseArchive,
        supplementDirectory: supplementDirectory,
      ),
    );

    await assertMinLinkPercentage(patcher);

    _exitIfDryRun(patcher: patcher, release: release);

    await logPatchSummary(
      app: app,
      releaseVersion: release.version,
      patcher: patcher,
      patchArtifactBundles: patchArtifactBundles,
    );

    // Write the build-trace summary after all compile/link work has
    // finished, for the patch's metadata, which is sent when the patch is
    // created, before its artifacts upload. It is written again once the
    // upload is done, for build history. No-op when tracing wasn't set up
    // (older Flutter pin).
    artifactBuilder.writeBuildTraceSummary();

    final metadata = await _createPatchMetadata(
      patcher: patcher,
      diffStatus: diffStatus,
      inferredReleaseVersion: inferredReleaseVersion,
    );
    _buildRun?.metadata = metadata.toJson();

    final patchToAddTo = _patchToAddTo;
    final patch = await blameFailureOn(
      _buildRun,
      BuildRunFailureReason.uploadFailed,
      () => patchToAddTo != null
          ? codePushClientWrapper.addPatchArtifacts(
              appId: appId,
              patch: CreatePatchResponse(
                id: patchToAddTo.id,
                number: patchToAddTo.number,
              ),
              platform: patcher.releaseType.releasePlatform,
              patchArtifactBundles: patchArtifactBundles,
            )
          : patcher.uploadPatchArtifacts(
              appId: appId,
              releaseId: release.id,
              metadata: metadata.toJson(),
              track: track,
              artifacts: patchArtifactBundles,
              rolloutPercentage: rolloutPercentage,
              rolloutSchedule: rolloutSchedule,
              linkKey: _link.key,
              gitSha: _link.checkout?.sha,
              gitDirty: _link.checkout?.dirty,
            ),
    );
    _logLink(
      platform: patcher.releaseType.releasePlatform,
      release: release,
      patch: patch,
    );
    _buildRun?.patchId = patch.id;
    if (app.crashReportingEnabled) {
      await patcher.uploadSymbolArtifacts(
        appId: appId,
        patchId: patch.id,
        architectures: patchArtifactBundles.keys,
      );
    }

    // Write the summary again now the upload is done, so build history's
    // timing counts it, as a release's does (see finalizeRelease).
    artifactBuilder.writeBuildTraceSummary();
    _buildRun?.metadata = metadata
        .copyWith(buildTraceSummary: buildTraceSession.summary?.toJson())
        .toJson();

    return PublishedPatch(
      platform: patcher.releaseType.releasePlatform,
      release: release,
      patch: patch,
      linkPercentage: patcher.linkPercentage,
    );
  }

  /// Says what linking did for [platform]'s [patch] on [release].
  void _logLink({
    required ReleasePlatform platform,
    required Release release,
    required CreatePatchResponse patch,
  }) {
    final link = patch.link;
    if (link == null) return;
    final name = platform.displayName;
    final number = patch.number;
    final others = [
      for (final p in link.platforms ?? const <String>[])
        ReleasePlatform.values
                .firstWhereOrNull((r) => r.value == p)
                ?.displayName ??
            p,
    ];
    switch (link.result) {
      case 'linked':
        final details = [
          ...others,
          if (_link.source == PatchLinkSource.commit)
            'commit ${_link.checkout!.shortSha}',
        ];
        final suffix = details.isEmpty ? '' : ' (${details.join(', ')})';
        logger.info('Linked $name to patch $number$suffix.');
      case 'reused':
        logger.info('Resumed the unfinished patch $number for $name.');
      case 'not_linked':
        final linkNumber = link.linkNumber;
        final linkedPatch = linkNumber == null
            ? 'the patch for other platforms'
            : 'patch $linkNumber';
        final newerPatch = switch (link.platformPatchNumber) {
          final number? => 'patch $number',
          null => 'a newer patch',
        };
        final why = switch (link.reason) {
          'platform_already_patched' =>
            '$name already published $linkedPatch under this key',
          'platform_has_newer_patch' =>
            '$name already has $newerPatch on release ${release.version}, '
                'so it cannot join $linkedPatch',
          'number_rolled_back' =>
            '$linkedPatch is rolled back on a platform, so $name cannot '
                'join it',
          _ => '$name could not join $linkedPatch',
        };
        logger.info('Not linked: $why. $name is patch $number.');
    }
  }

  /// Exits if [release] was built with a Flutter version older than
  /// [Patcher.minimumFlutterVersion]. Must run with the release's Flutter
  /// revision in scope. A version that can't be determined is let through.
  Future<void> _assertReleaseFlutterVersionSupported({
    required Patcher patcher,
    required Release release,
  }) async {
    final minimumFlutterVersion = patcher.minimumFlutterVersion;
    if (minimumFlutterVersion == null) return;

    final flutterVersion = await shorebirdFlutter.getVersion();
    if (flutterVersion == null ||
        flutterVersion.satisfiesFloor(minimumFlutterVersion)) {
      return;
    }

    final flutterVersionAndRevision = await shorebirdFlutter
        .getVersionAndRevision();
    final cliName = patcher.releaseType.cliName;
    _buildRun?.failWith(BuildRunFailureReason.releaseIncompatible);
    throw CommandError(
      message:
          'Release ${release.version} was built with Flutter '
          '$flutterVersionAndRevision, but patching with `$cliName` needs at '
          'least Flutter $minimumFlutterVersion (see '
          '$supportedFlutterVersionsUrl).',
      hint:
          'A release cannot change Flutter versions, so create a new release '
          'with the latest Flutter to patch. Run: '
          '${patcher.releaseType.releaseCommand()}',
      exitCode: ExitCode.software,
    );
  }

  /// Warns if shorebird.yaml asks for `patch_verification: install_only` and
  /// [release] was built with a Flutter whose updater never checks patch
  /// signatures in that mode (since updater#352), so devices on [release]
  /// install this patch without checking its signature. Only a new release
  /// can change that, so the patch goes ahead. Must run with the release's
  /// Flutter revision in scope.
  ///
  /// Reads today's shorebird.yaml, which is the release's unless it has
  /// changed since.
  Future<void> _warnIfInstallOnlySkipsSignatureCheck({
    required Release release,
  }) async {
    final patchVerification = shorebirdEnv
        .getShorebirdYaml()
        ?.patchVerification;
    if (patchVerification != PatchVerification.installOnly) return;
    if (!installOnlySkipsSignatureCheck(shorebirdEnv.shorebirdEngineRevision)) {
      return;
    }
    final flutterVersion = await shorebirdFlutter.getVersionAndRevision();
    logger.warn(
      '''
shorebird.yaml sets `patch_verification: install_only`, which does not check patch signatures with Flutter $flutterVersion, the Flutter release ${release.version} was built with. If the release was built with this setting, devices on it will install this patch without checking its signature.
To have signatures checked, remove `patch_verification` from shorebird.yaml (or set it to `strict`) and create a new release, or release with a Flutter version that checks signatures in install_only mode, such as --flutter-version=3.41.8.''',
    );
  }

  /// Warns if Shorebird marked the Flutter revision [release] was built with
  /// as having a known problem on [patcher]'s platform. A patch can't change
  /// the Flutter a release was built with, so the patch goes ahead; the fix
  /// is a new release.
  void _warnIfFlutterRevisionHasKnownIssue({
    required Release release,
    required Patcher patcher,
  }) {
    final issue = release.flutterRevisionIssue;
    if (issue == null) return;
    final platform = patcher.releaseType.releasePlatform;
    final platforms = issue.platforms;
    if (platforms != null && !platforms.contains(platform)) return;

    String flutterBuild(String? version, String revision) {
      final shortRevision = revision.length > 10
          ? revision.substring(0, 10)
          : revision;
      return version == null
          ? 'Flutter revision $shortRevision'
          : 'Flutter $version ($shortRevision)';
    }

    final details = issue.details;
    final fixedInRevision = issue.fixedInRevision;
    final releaseWith = fixedInRevision == null
        ? 'a Flutter version without this problem'
        : '${flutterBuild(issue.fixedInVersion, fixedInRevision)} or newer';
    final builtWith = flutterBuild(
      release.flutterVersion,
      release.flutterRevision,
    );
    final problem =
        'Release ${release.version} was built with $builtWith, which has a '
        'known problem on ${platform.displayName}: ${issue.summary}';
    final fix =
        'A patch cannot change the Flutter version a release was built with. '
        'To fix this, create a new release with $releaseWith.';
    logger.warn([problem, ?details, fix].join('\n'));
  }

  /// Reports a successful check and exits with success if this is a dry run.
  /// Exits with an error when [patcher]'s link percentage is below
  /// `--min-link-percentage`. Runs before `--dry-run` exits, so a dry run
  /// fails the same way the real run would.
  @visibleForTesting
  Future<void> assertMinLinkPercentage(Patcher patcher) async {
    final linkPercentage = patcher.linkPercentage;
    final minLinkPercentageRaw =
        results[CommonArguments.minLinkPercentage.name] as String;
    final minLinkPercentage = int.tryParse(minLinkPercentageRaw);
    if (minLinkPercentage == null ||
        minLinkPercentage < CommonArguments.minLinkPercentageMin ||
        minLinkPercentage > CommonArguments.minLinkPercentageMax) {
      usageException(
        '--min-link-percentage must be an integer between '
        '${CommonArguments.minLinkPercentageMin} and '
        '${CommonArguments.minLinkPercentageMax} '
        '(got $minLinkPercentageRaw).',
      );
    }
    if (linkPercentage != null && linkPercentage < minLinkPercentage) {
      _buildRun?.failWith(BuildRunFailureReason.linkPercentage);
      throw CommandError(
        message:
            'The link percentage of this patch '
            '(${Patcher.formatLinkPercentage(linkPercentage)}%) is below '
            'the minimum threshold ($minLinkPercentage%).',
        hint:
            'Not publishing. Lower --min-link-percentage to accept this '
            'patch, or see ${Patcher.debugInfoFile.path} for what could not '
            'be linked.',
        exitCode: ExitCode.software,
      );
    }
  }

  void _exitIfDryRun({required Patcher patcher, required Release release}) {
    final dryRun = results['dry-run'] == true;
    if (!dryRun) return;

    if (isJsonMode) {
      emitJsonSuccess({
        'dry_run': true,
        'app_id': appId,
        'platform': patcher.releaseType.releasePlatform.name,
        'release_id': release.id,
        'release_version': release.version,
        'link_percentage': patcher.linkPercentage,
        'add_to_patch': ?addToPatchNumber,
      });
    } else {
      logger
        ..info('No issues detected.')
        ..info('The server may enforce additional checks.');
    }
    throw ProcessExit(ExitCode.success.code);
  }

  /// The metadata uploaded with the patch.
  Future<CreatePatchMetadata> _createPatchMetadata({
    required Patcher patcher,
    required DiffStatus diffStatus,
    required bool inferredReleaseVersion,
  }) {
    final baseMetadata = CreatePatchMetadata(
      releasePlatform: patcher.releaseType.releasePlatform,
      usedIgnoreAssetChangesFlag: allowAssetDiffs,
      hasAssetChanges: diffStatus.hasAssetChanges,
      usedIgnoreNativeChangesFlag: allowNativeDiffs,
      hasNativeChanges: diffStatus.hasNativeChanges,
      inferredReleaseVersion: inferredReleaseVersion,
      usedDefaultTrack: _usedDefaultTrack,
      isSigned:
          results.wasParsed(CommonArguments.privateKeyArg.name) ||
          results.wasParsed(CommonArguments.signCmd.name),
      environment: BuildEnvironmentMetadata(
        flutterRevision: shorebirdEnv.flutterRevision,
        operatingSystem: platform.operatingSystem,
        operatingSystemVersion: platform.operatingSystemVersion,
        shorebirdVersion: packageVersion,
        shorebirdYaml: shorebirdEnv.getShorebirdYaml()!,
        usesShorebirdCodePushPackage: shorebirdEnv.usesShorebirdCodePushPackage,
      ),
      // Attach the build-trace summary if the build produced one.
      // Null for older Flutter pins without the --shorebird-trace
      // flag or when trace parsing failed; uploader sends
      // null-as-omitted.
      buildTraceSummary: buildTraceSession.summary?.toJson(),
    );
    return patcher.updatedCreatePatchMetadata(baseMetadata);
  }

  /// Prompts the user for the specific release to patch.
  Future<Release> promptForRelease(ReleaseType releaseType) async {
    final platform = releaseType.releasePlatform;
    final releases = await codePushClientWrapper.getReleases(appId: appId);

    final releasesForPlatform = releases.where(
      (release) => release.hasPlatform(platform),
    );

    if (releasesForPlatform.isEmpty) {
      throw _noReleasesToPatch(releaseType);
    }

    return chooseRelease(
      releases: releasesForPlatform,
      action: 'patch',
    );
  }

  /// The error to throw when there is nothing to patch for [releaseType].
  ///
  /// The app id comes from the flavor's entry under `flavors` in
  /// shorebird.yaml when --flavor is passed, otherwise from `app_id`.
  CommandError _noReleasesToPatch(ReleaseType releaseType) {
    final flavor = this.flavor;
    final checkAppId = flavor == null
        ? 'check app_id in shorebird.yaml or pass --flavor'
        : 'check flavors.$flavor in shorebird.yaml';
    final releaseCommand = [
      releaseType.releaseCommand(),
      if (flavor != null) '--flavor=$flavor',
    ].join(' ');
    return CommandError(
      message:
          'No ${releaseType.releasePlatform.displayName} releases found for '
          'app $appId.',
      hint:
          'A patch needs a release to apply to (if this is the wrong app, '
          '$checkAppId). Run: $releaseCommand',
    );
  }

  /// Asserts that the release contains a platform for the given [patcher].
  void assertReleaseContainsPlatform({
    required Release release,
    required Patcher patcher,
  }) {
    final releasePlatform = patcher.releaseType.releasePlatform;
    if (!release.hasPlatform(releasePlatform)) {
      final releaseCommand = patcher.releaseType.releaseCommand(
        releaseVersion: release.version,
      );
      _buildRun?.failWith(BuildRunFailureReason.releaseIncompatible);
      throw CommandError(
        message:
            'Release ${release.version} has no '
            '${releasePlatform.displayName} build.',
        hint: 'Run: $releaseCommand',
        exitCode: ExitCode.software,
      );
    }
  }

  /// Asserts that the provided [release] is active.
  void assertReleaseIsActive({
    required Release release,
    required Patcher patcher,
  }) {
    if (!release.isActiveOn(patcher.releaseType.releasePlatform)) {
      final releaseCommand = patcher.releaseType.releaseCommand(
        releaseVersion: release.version,
      );
      _buildRun?.failWith(BuildRunFailureReason.releaseIncompatible);
      throw CommandError(
        message:
            'Release ${release.version} is incomplete: the release command '
            'that created it was stopped or failed.',
        hint:
            'Re-run the release for this version, or create a new one. '
            'Run: $releaseCommand',
        exitCode: ExitCode.software,
      );
    }
  }

  /// Exits if [release] embeds the customer's own key on [patcher]'s
  /// platform but no key was passed to sign the patch with: devices running
  /// the release reject an unsigned patch.
  void _assertCanSignForRelease({
    required Release release,
    required Patcher patcher,
  }) {
    final signingMode =
        release.platforms[patcher.releaseType.releasePlatform]?.signingMode;
    if (signingMode != ReleaseSigningMode.customer.value) return;

    final publicKeyPath = CommonArguments.publicKeyArg.name;
    final privateKeyPath = CommonArguments.privateKeyArg.name;
    final publicKeyCmd = CommonArguments.publicKeyCmd.name;
    final signCmd = CommonArguments.signCmd.name;
    final hasPublicKey =
        results.wasParsed(publicKeyPath) || results.wasParsed(publicKeyCmd);
    final hasSigner =
        results.wasParsed(privateKeyPath) || results.wasParsed(signCmd);
    if (hasPublicKey && hasSigner) return;

    usageException(
      'Release ${release.version} was signed with your own key, so its '
      'patches must be too. Pass the same public key as the release, with '
      '--$publicKeyPath and --$privateKeyPath, or --$publicKeyCmd and '
      '--$signCmd.',
    );
  }

  /// Exits before building if [app]'s enterprise requires patch signing and
  /// [release]'s build for [patcher]'s platform checks no signature: built
  /// with `--no-patch-signing`, or by a CLI that predates release signing.
  /// The server refuses every patch to such a release.
  void _assertReleaseSignedForPolicy({
    required AppMetadata app,
    required Release release,
    required Patcher patcher,
  }) {
    if (app.patchSigningRequired != true) return;
    final platform = patcher.releaseType.releasePlatform;
    final signingMode = release.platforms[platform]?.signingMode;
    if (signingMode == ReleaseSigningMode.managed.value ||
        signingMode == ReleaseSigningMode.customer.value) {
      return;
    }
    _buildRun?.failWith(BuildRunFailureReason.releaseIncompatible);
    throw CommandError(
      message:
          '${app.enterpriseName ?? 'Your enterprise'} requires patch '
          'signing, and release ${release.version} (${platform.displayName}) '
          "wasn't built with signing, so its devices can't verify a patch.",
      hint: 'Ship a new release and patch that.',
      exitCode: ExitCode.noPerm,
    );
  }

  /// Ensures the diff between the release and patch archives is safe to patch.
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File patchArchive,
    required File releaseArchive,
    required Patcher patcher,
  }) async {
    try {
      // Must be awaited inside the try, otherwise the catch clauses below never
      // see the failure and the patch exits with an unhandled exception.
      return await patcher.assertUnpatchableDiffs(
        releaseArtifact: releaseArtifact,
        releaseArchive: releaseArchive,
        patchArchive: patchArchive,
      );
    } on UserCancelledException catch (e) {
      _failWithChanges({e.change}, status: e.status);
      logger.err('Aborting.');
      throw PromptDeclinedExit();
    } on ArchiveException catch (e) {
      throw CommandError(
        message: 'Could not compare the patch with the release: ${e.message}',
        hint: damagedReleaseArtifactHint(patcher.releaseType),
        exitCode: ExitCode.software,
      );
    } on UnpatchableChangeException catch (e) {
      // The diff checker has already listed the changes.
      final changes = e.changes;
      final native = changes.contains(UnpatchableChange.native);
      _failWithChanges(changes, status: e.status);
      final releaseCommand = patcher.releaseType.releaseCommand(
        releaseVersion: '<new version>',
      );
      throw CommandError(
        message:
            'Not publishing: '
            '${changes.map((c) => c.description).join(' and ')} changed '
            "since the release, and a patch can't include those changes.",
        hint:
            'To ship these changes, create a new release. '
            'Run: $releaseCommand\n'
            'To publish the patch without them, pass '
            '${changes.map((c) => c.flag).join(' ')}.'
            '${native ? _nativeCrashWarning : ''}',
        exitCode: ExitCode.software,
      );
    }
  }

  /// Records in the build run that the patch stopped on [changes], and
  /// keeps [status], everything the diff check found, for the run's
  /// metadata.
  void _failWithChanges(
    Set<UnpatchableChange> changes, {
    required DiffStatus? status,
  }) {
    final native = changes.contains(UnpatchableChange.native);
    final asset = changes.contains(UnpatchableChange.asset);
    _diffStatus =
        status ?? DiffStatus(hasAssetChanges: asset, hasNativeChanges: native);
    _buildRun?.failWith(
      native
          ? BuildRunFailureReason.nativeDiffs
          : BuildRunFailureReason.assetDiffs,
    );
  }

  /// Logs a summary of the patch to be created, including:
  /// - The app name and ID
  /// - The release version
  /// - The platform
  /// - The track
  /// - The link percentage (if iOS)
  /// - The debug info file (if iOS)
  Future<void> logPatchSummary({
    required AppMetadata app,
    required String releaseVersion,
    required Patcher patcher,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final archMetadata = patchArtifactBundles.keys.map((arch) {
      final size = formatBytes(patchArtifactBundles[arch]!.size);
      return '${arch.name} ($size)';
    });
    final rolloutSummary = switch ((rolloutSchedule, rolloutPercentage)) {
      (final RolloutSchedule schedule, _) =>
        '(${formatRolloutSchedule(schedule)})',
      (_, final double percentage) when percentage < 100 =>
        '(${formatRolloutPercentage(percentage)})',
      _ => null,
    };
    final rollout = rolloutSummary == null
        ? ''
        : ' ${lightCyan.wrap(rolloutSummary)}';
    final trackSummary = switch (track) {
      DeploymentTrack.staging => '🟠 Track: ${lightCyan.wrap('Staging')}',
      DeploymentTrack.beta => '🔵 Track: ${lightCyan.wrap('Beta')}',
      DeploymentTrack.stable => '🟢 Track: ${lightCyan.wrap('Stable')}',
      final String trackName => '⚪️ Track: ${lightCyan.wrap(trackName)}',
    };

    final linkPercentage = patcher.linkPercentage;
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(patcher.releaseType.releasePlatform.displayName)} ${lightCyan.wrap('[${archMetadata.join(', ')}]')}''',
      '$trackSummary$rollout',
      if (linkPercentage != null &&
          linkPercentage < Patcher.linkPercentageWarningThreshold)
        '''🔍 Debug Info: ${lightCyan.wrap(Patcher.debugInfoFile.path)}''',
    ];

    logger.info('''

${styleBold.wrap(lightGreen.wrap(_patchToAddTo == null ? '🚀 Ready to publish a new patch!' : '🚀 Ready to add to patch ${_patchToAddTo!.number}!'))}

${summary.join('\n')}
''');
  }

  /// Downloads the given [releaseArtifact].
  Future<File> downloadReleaseArtifact({
    required ReleaseArtifact releaseArtifact,
  }) async {
    final File artifactFile;
    try {
      artifactFile = await artifactManager.downloadReleaseArtifact(
        releaseArtifact,
        message: 'Downloading ${releaseArtifact.arch}',
      );
    } on Exception catch (error) {
      throw CommandError(
        message: 'Could not download the release artifact: $error',
        hint: 'Run the command again once that is fixed.',
        exitCode: ExitCode.software,
      );
    }

    return artifactFile;
  }
}

/// Executes [build] to build the artifact and includes
/// special handling thrown exceptions such as [ArtifactBuildException].
/// Calls [onBuildFailed] when the build itself fails, not when a step it
/// takes already reported why it stopped.
Future<R> _tryBuildingArtifact<R>(
  Future<R> Function() build, {
  void Function()? onBuildFailed,
}) async {
  try {
    return await build();
  } on ArtifactBuildException catch (e) {
    onBuildFailed?.call();
    throw CommandError(
      message: e.message,
      hint: e.fixRecommendation.isNullOrEmpty ? null : e.fixRecommendation,
      exitCode: ExitCode.software,
    );
  } on ProcessExit {
    // The build already reported why it stopped.
    rethrow;
  } on Exception catch (e) {
    onBuildFailed?.call();
    throw CommandError(
      message: 'Failed to build patch artifacts: $e',
      exitCode: ExitCode.software,
    );
  }
}

/// Extension on list of releases for sorting the releases.
extension SortReleases on List<Release> {
  /// Sort the list of releases by when they were last updated ascending.
  void sortByUpdatedAt() => sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
}

/// {@template published_patch}
/// One platform's outcome of `shorebird patch`: which release it patched,
/// the patch that resulted, and how much of the release's Dart code the
/// patch could share with it.
/// {@endtemplate}
class PublishedPatch {
  /// {@macro published_patch}
  const PublishedPatch({
    required this.platform,
    required this.release,
    required this.patch,
    required this.linkPercentage,
    this.alreadyPublished = false,
  });

  /// The platform the patch was built for.
  final ReleasePlatform platform;

  /// The release the patch applies to.
  final Release release;

  /// The patch as the server created it.
  final CreatePatchResponse patch;

  /// The share of Dart code linked against the release, as a percentage,
  /// where the platform reports one.
  final double? linkPercentage;

  /// Whether an earlier run published this patch, so this run skipped the
  /// platform.
  final bool alreadyPublished;

  /// The shape written into the `--json` envelope.
  Map<String, dynamic> toJson() => {
    'platform': platform.name,
    'release_id': release.id,
    'release_version': release.version,
    'patch_id': patch.id,
    'patch_number': patch.number,
    'link_percentage': linkPercentage,
    'already_published': alreadyPublished,
    'link_result': patch.link?.result,
  };
}
