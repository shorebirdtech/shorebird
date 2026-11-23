import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/extensions/release_patch.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Whether [error] is the server refusing to act on every platform under a
/// patch number because they are in different states.
bool isPlatformsDiffer(Object error) =>
    error is ApiErrorExit && error.error.code == patchPlatformsDifferCode;

/// {@template patch_number}
/// Every patch a release has under one patch number. Patches built from the
/// same commit for different platforms share a number, each with its own
/// track and rolled-back state.
/// {@endtemplate}
class PatchNumber {
  /// {@macro patch_number}
  PatchNumber({required this.number, required this.rows})
    : assert(rows.isNotEmpty, 'A patch number has at least one patch.');

  /// The patch number.
  final int number;

  /// The server's entries for [number], in its order: within a number the
  /// least-promoted comes first, and a patch on several tracks appears once
  /// for each.
  final List<ReleasePatch> rows;

  /// One entry per patch, the first the server lists for it.
  List<ReleasePatch> get patches {
    final seen = <int>{};
    return [
      for (final row in rows)
        if (seen.add(row.id)) row,
    ];
  }

  /// The platforms with a patch under [number], or empty when the server
  /// does not say (patches created before it recorded platforms, with no
  /// artifacts).
  List<ReleasePlatform> get platforms => {
    for (final row in rows) ?row.resolvedPlatform,
  }.toList();

  /// [platform]'s patch under [number], or the first patch when the server
  /// does not say which platform patches are for.
  ReleasePatch? patchFor(ReleasePlatform platform) => platforms.isEmpty
      ? patches.first
      : patches.firstWhereOrNull((p) => p.resolvedPlatform == platform);

  /// The tracks [patch] is on, as `patches list` shows them, or null when it
  /// is on none.
  String? tracksOf(ReleasePatch patch) {
    final tracks = [
      for (final row in rows)
        if (row.id == patch.id) ?formatPatchTrack(row),
    ];
    return tracks.isEmpty ? null : tracks.join(' + ');
  }

  /// The tracks [patch] is on, without rollout percentages.
  Set<String> _channelsOf(ReleasePatch patch) => {
    for (final row in rows)
      if (row.id == patch.id) ?row.channel,
  };

  /// Whether the patches under [number] are on different tracks. Patches on
  /// the same track at different rollout percentages are not.
  bool get tracksDiffer =>
      patches
          .map((p) => (_channelsOf(p).toList()..sort()).join(','))
          .toSet()
          .length >
      1;

  /// [patch]'s track and whether it is rolled back, e.g. `stable, rolled
  /// back`.
  String stateOf(ReleasePatch patch) => [
    tracksOf(patch) ?? 'no track',
    if (patch.isRolledBack) 'rolled back',
  ].join(', ');

  /// The name of [patch]'s platform, or `patch <id>` when the server does
  /// not say.
  static String platformName(ReleasePatch patch) =>
      patch.resolvedPlatform?.displayName ?? 'patch ${patch.id}';
}

/// Groups [patches] by number, in the order the numbers first appear.
List<PatchNumber> groupByNumber(List<ReleasePatch> patches) => [
  for (final MapEntry(key: number, value: rows) in groupBy(
    patches,
    (ReleasePatch p) => p.number,
  ).entries)
    PatchNumber(number: number, rows: rows),
];

/// One line describing [patch]: its number, platforms, track and whether it
/// is rolled back, saying so when its platforms are on different tracks.
///
/// [color] highlights the number; leave it off for text that may end up in
/// `--json` output.
String formatPatchNumberLine(PatchNumber patch, {bool color = true}) {
  final number = color
      ? lightCyan.wrap('#${patch.number}')
      : '#${patch.number}';
  final platforms = patch.platforms.map((p) => p.value).join(', ');
  final patches = patch.patches;
  final each = [
    for (final p in patches)
      '${_platformValue(p)}: ${patch.tracksOf(p) ?? 'no track'}',
  ].join(', ');
  final tracks = patches.map(patch.tracksOf).toSet();
  final String track;
  if (patch.tracksDiffer) {
    track = '  on different tracks ($each)';
  } else if (tracks.length > 1) {
    // One track, rolling out to different shares of each platform.
    track = '  track: ${patch.patches.first.channel} ($each)';
  } else {
    track = switch (tracks.single) {
      final tracks? => '  track: $tracks',
      null => '  [no track]',
    };
  }
  final rolledBack = patches.where((p) => p.isRolledBack).toList();
  final rolledBackLabel = rolledBack.isEmpty
      ? ''
      : rolledBack.length == patches.length
      ? '  [rolled back]'
      : '  [rolled back on ${rolledBack.map(_platformValue).join(', ')}]';
  return [
    number,
    if (platforms.isNotEmpty) '  $platforms',
    track,
    rolledBackLabel,
  ].join();
}

/// [patch]'s platform as `--platforms` takes it, or its id when the server
/// does not say.
String _platformValue(ReleasePatch patch) =>
    patch.resolvedPlatform?.value ?? '${patch.id}';

/// Shared lookup of a release's patches for the `patches` subcommands.
mixin PatchLookup on ShorebirdCommand {
  /// The option naming the platforms whose patches under a number to act on.
  static const platformsArgName = 'platforms';

  /// Adds `--platforms`, which limits the command to those platforms'
  /// patches under the number. [action] completes "The platforms whose
  /// patches to ...".
  void addPlatformsOption({required String action}) {
    argParser.addMultiOption(
      platformsArgName,
      help:
          'The platforms whose patches to $action, when patches for several '
          'platforms share the patch number. Defaults to all of them.',
      allowed: ReleasePlatform.values.map((p) => p.value),
    );
  }

  /// The platforms `--platforms` names, or null when it was not given.
  List<ReleasePlatform>? get requestedPlatforms {
    final values = results[platformsArgName] as List<String>?;
    if (values == null || values.isEmpty) return null;
    return values.map(ReleasePlatform.fromJson).toSet().toList();
  }

  /// Fetches release [releaseVersion] of [appId] and its patches.
  ///
  /// In `--json` mode a failed fetch is reported as a `fetch_failed` error
  /// with [fetchFailedMessage] (by default "Failed to fetch patches for
  /// release ...") and its exit code is returned; otherwise the failure is
  /// rethrown.
  ///
  /// Returns the release and its patches on success, or `errorCode` after
  /// reporting the failure.
  Future<({Release? release, List<ReleasePatch> patches, int? errorCode})>
  fetchReleasePatches({
    required String appId,
    required String releaseVersion,
    String? fetchFailedMessage,
  }) async {
    late final Release release;
    late final List<ReleasePatch> patches;
    final fetchError = await guardApiCall(
      () async {
        release = await codePushClientWrapper.getRelease(
          appId: appId,
          releaseVersion: releaseVersion,
        );
        patches = await codePushClientWrapper.getReleasePatches(
          appId: appId,
          releaseId: release.id,
        );
      },
      code: JsonErrorCode.fetchFailed,
      message:
          fetchFailedMessage ??
          'Failed to fetch patches for release "$releaseVersion".',
    );
    if (fetchError != null) {
      return (release: null, patches: <ReleasePatch>[], errorCode: fetchError);
    }
    return (release: release, patches: patches, errorCode: null);
  }

  /// Finds every patch numbered [patchNumber] among [patches] of release
  /// [releaseVersion].
  ///
  /// When there is none, reports it as a usage error and returns its exit
  /// code: that the release has no patches at all, or else which patch
  /// numbers it does have.
  ({PatchNumber? patch, int? errorCode}) findPatchNumberOrReport({
    required List<ReleasePatch> patches,
    required int patchNumber,
    required String releaseVersion,
  }) {
    final numbers = groupByNumber(patches);
    final patch = numbers.firstWhereOrNull((n) => n.number == patchNumber);
    if (patch != null) return (patch: patch, errorCode: null);

    if (patches.isEmpty) {
      final errorCode = reportError(
        message: 'No patches found for release "$releaseVersion".',
      );
      return (patch: null, errorCode: errorCode);
    }

    final available = numbers
        .map((n) => '\n  ${formatPatchNumberLine(n, color: false)}')
        .join();
    final errorCode = reportError(
      message:
          'No patch found with number $patchNumber '
          'for release "$releaseVersion".',
      hint: 'Available patches:$available',
    );
    return (patch: null, errorCode: errorCode);
  }

  /// Decides which of [patch]'s platforms to [verb].
  ///
  /// With `--platforms`, those platforms, after checking each has a patch
  /// under the number. Without it, every platform: when there are several
  /// and the CLI can ask, it lists them and asks "<[verb]> all of
  /// them<[confirmSuffix]>?" first, unless [confirm] is false.
  ///
  /// Returns the platforms to send (null to send none, which the server
  /// takes as every platform) and their patches, or `errorCode` after
  /// reporting the failure.
  ({
    List<ReleasePlatform>? platforms,
    List<ReleasePatch> patches,
    int? errorCode,
  })
  choosePlatforms({
    required PatchNumber patch,
    required String releaseVersion,
    required String verb,
    bool confirm = true,
    String confirmSuffix = '',
  }) {
    final known = patch.platforms;
    final requested = requestedPlatforms;
    if (requested != null) {
      final missing = known.isEmpty
          ? const <ReleasePlatform>[]
          : requested.where((p) => !known.contains(p)).toList();
      if (missing.isNotEmpty) {
        final errorCode = reportError(
          message:
              'Patch ${patch.number} on release $releaseVersion has no '
              '${missing.map((p) => p.displayName).join(' or ')} patch.',
          hint:
              'It has patches for '
              '${known.map((p) => p.displayName).join(', ')}.',
        );
        return (platforms: null, patches: const [], errorCode: errorCode);
      }
      return (
        platforms: requested,
        patches: [for (final p in requested) ?patch.patchFor(p)],
        errorCode: null,
      );
    }

    if (confirm) {
      confirmAllPlatforms(
        patch: patch,
        releaseVersion: releaseVersion,
        verb: verb,
        confirmSuffix: confirmSuffix,
      );
    }
    return (platforms: null, patches: patch.patches, errorCode: null);
  }

  /// When [patch] has several platforms and the CLI can ask, lists them and
  /// asks "<[verb]> all of them<[confirmSuffix]>?", throwing
  /// [PromptDeclinedExit] when the answer is no.
  void confirmAllPlatforms({
    required PatchNumber patch,
    required String releaseVersion,
    required String verb,
    String confirmSuffix = '',
  }) {
    final known = patch.platforms;
    if (known.length < 2 || !shorebirdEnv.canAcceptUserInput) return;
    logger.info(
      'Patch ${patch.number} on release $releaseVersion has patches for '
      '${known.length} platforms:',
    );
    for (final p in patch.patches) {
      logger.info('  ${PatchNumber.platformName(p)}: ${patch.stateOf(p)}');
    }
    final proceed = logger.confirm(
      '${verb[0].toUpperCase()}${verb.substring(1)} all of them'
      '$confirmSuffix?',
    );
    if (!proceed) {
      logger.info(
        'To $verb only some, pass --$platformsArgName, e.g. '
        '--$platformsArgName=${known.first.value}.',
      );
      throw PromptDeclinedExit();
    }
  }

  /// This command run again on [patch] for [platforms] only, with
  /// [extraArgs] and the `--app-id` and `--flavor` given to this run.
  String commandForPlatforms({
    required PatchNumber patch,
    required String releaseVersion,
    required List<ReleasePlatform> platforms,
    List<String> extraArgs = const [],
  }) => [
    'shorebird $fullCommandName',
    '--release-version=$releaseVersion',
    '--patch-number=${patch.number}',
    ...extraArgs,
    for (final option in const ['app-id', 'flavor'])
      if (argParser.options.containsKey(option))
        if (results[option] case final String value) '--$option=$value',
    '--$platformsArgName=${platforms.map((p) => p.value).join(',')}',
  ].join(' ');

  /// Says that the platforms under [patch] are in different states, so the
  /// server would refuse to act on all of them without `--platforms`: what
  /// each one's state is and how to act on [suggested] alone. Returns the
  /// exit code to fail with.
  ///
  /// [reason] is the error to report first when the server has not already
  /// reported one, and the only output in `--json` mode. With it, the run
  /// fails as a usage error; without it, as the server's error.
  int reportPlatformsDiffer({
    required PatchNumber patch,
    required String releaseVersion,
    required List<ReleasePlatform> suggested,
    List<String> extraArgs = const [],
    String? reason,
  }) {
    final command = commandForPlatforms(
      patch: patch,
      releaseVersion: releaseVersion,
      platforms: suggested.isEmpty ? patch.platforms : suggested,
      extraArgs: extraArgs,
    );
    if (reason != null && isJsonMode) {
      return reportError(
        message: reason,
        hint: 'To choose which to change, run: $command',
      );
    }
    if (reason != null) logger.err(reason);
    logger.info(
      'Patch ${patch.number} on release $releaseVersion has patches for '
      'several platforms, in different states:',
    );
    for (final p in patch.patches) {
      logger.info('  ${PatchNumber.platformName(p)}: ${patch.stateOf(p)}');
    }
    logger.info(
      'To choose which to change, run:\n  ${lightCyan.wrap(command)}',
    );
    return reason == null ? ExitCode.software.code : ExitCode.usage.code;
  }
}
