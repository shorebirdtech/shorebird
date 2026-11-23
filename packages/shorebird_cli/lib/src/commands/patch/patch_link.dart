import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:uuid/uuid.dart';

/// The commit a patch is built from.
@immutable
class GitCheckout {
  /// Creates a [GitCheckout] at [sha], [dirty] when the working tree has
  /// uncommitted or untracked files.
  const GitCheckout({required this.sha, required this.dirty});

  /// The full SHA of HEAD.
  final String sha;

  /// Whether the working tree has uncommitted changes or untracked files.
  final bool dirty;

  /// The first seven characters of [sha], as `git log --oneline` shows it.
  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

/// Where a [PatchLinkPlan.key] came from.
enum PatchLinkSource {
  /// `--patch-key`.
  flag,

  /// The SHA of HEAD.
  commit,

  /// Generated for this run, so its platforms share a number.
  random,
}

/// The key `shorebird patch` sends with every platform's patch so that
/// patches built from the same source share a number, and the commit it
/// records with each.
@immutable
class PatchLinkPlan {
  /// Creates a [PatchLinkPlan].
  const PatchLinkPlan({this.key, this.source, this.checkout});

  /// No key and no commit.
  static const none = PatchLinkPlan();

  /// The key, or null to not link.
  final String? key;

  /// Where [key] came from, or null when there is no key.
  final PatchLinkSource? source;

  /// The commit the patch is built from, or null outside a git checkout.
  final GitCheckout? checkout;

  /// Whether a platform the server already published under [key] can be
  /// skipped: true only when [key] is the commit's SHA and the tree is
  /// clean, so the key names exactly what would be built again. The server
  /// does not return the commit a patch was built from, so a `--patch-key`
  /// patch cannot be matched to this commit.
  bool get canSkipPublished =>
      source == PatchLinkSource.commit && checkout != null && !checkout!.dirty;
}

/// Reads HEAD and whether the working tree is clean for the git checkout
/// containing [directory]. Returns null when [directory] is not in a git
/// checkout, has no commits, or git is not installed.
Future<GitCheckout?> readGitCheckout(Directory directory) async {
  try {
    final sha = await git.revParse(revision: 'HEAD', directory: directory.path);
    final status = await git.statusPorcelain(directory: directory.path);
    return GitCheckout(sha: sha, dirty: status.trim().isNotEmpty);
  } on ProcessException {
    return null;
  }
}

/// Decides how this run of `shorebird patch` links its [platforms], logging
/// why when it does not link.
///
/// In order: [patchKey] (`--patch-key`); no key with [noLink] (`--no-link`);
/// HEAD's SHA on a clean tree, or on a dirty tree on CI, where uncommitted
/// files are usually build output; no key on a dirty tree elsewhere; and
/// outside a git checkout, a random key shared by [platforms] when there are
/// several.
Future<PatchLinkPlan> resolvePatchLink({
  required String? patchKey,
  required bool noLink,
  required List<ReleasePlatform> platforms,
  required Directory projectRoot,
}) async {
  final checkout = await readGitCheckout(projectRoot);
  if (patchKey != null) {
    return PatchLinkPlan(
      key: patchKey,
      source: PatchLinkSource.flag,
      checkout: checkout,
    );
  }
  if (noLink) return PatchLinkPlan(checkout: checkout);

  if (checkout != null) {
    if (!checkout.dirty) {
      return PatchLinkPlan(
        key: checkout.sha,
        source: PatchLinkSource.commit,
        checkout: checkout,
      );
    }
    if (shorebirdEnv.isRunningOnCI) {
      logger.info(
        'The working tree has uncommitted changes. On CI these are usually '
        'build output, so this patch is linked by commit '
        '${checkout.shortSha} and recorded as built from a modified tree.',
      );
      return PatchLinkPlan(
        key: checkout.sha,
        source: PatchLinkSource.commit,
        checkout: checkout,
      );
    }
    logger.info(
      'Not linked: the working tree has uncommitted changes, so this patch '
      'may not match commit ${checkout.shortSha}. To give it the same patch '
      'number as patches for other platforms, commit your changes first, or '
      'pass the same ${lightCyan.wrap('--patch-key=<key>')} to each '
      '`shorebird patch`.',
    );
    return PatchLinkPlan(checkout: checkout);
  }

  if (platforms.length > 1) {
    return PatchLinkPlan(
      key: const Uuid().v4(),
      source: PatchLinkSource.random,
    );
  }
  logger.detail(
    'Not linked: not a git checkout. Pass --patch-key=<key> to give this '
    'patch the same number as patches for other platforms.',
  );
  return PatchLinkPlan.none;
}
