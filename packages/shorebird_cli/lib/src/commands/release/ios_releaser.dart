import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/apple_build_helpers.dart';
import 'package:shorebird_cli/src/commands/patch/apple_patcher_mixin.dart';
import 'package:shorebird_cli/src/commands/release/apple_releaser_mixin.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/apple/apple.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/split_debug_info.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template ios_releaser}
/// Functions to build and publish an iOS release.
/// {@endtemplate}
class IosReleaser extends Releaser with AppleReleaserMixin {
  /// {@macro ios_releaser}
  IosReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.ios;

  @override
  String get supplementPlatformSubdir => 'ios';

  @override
  String get supplementArtifactArch => 'ios_supplement';

  @override
  String get artifactDisplayName => 'iOS app';

  @override
  List<Validator> get applePlatformValidators => doctor.iosCommandValidators;

  @override
  Future<void> assertArgsAreValid() async {
    assertReleaseVersionFlagNotProvided();
    argResults.assertValidExportOptionsPlistArg();
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    if (!argResults.appleCodesign) {
      logger
        ..info(
          '''Building for device with codesigning disabled. You will have to manually codesign before deploying to device.''',
        )
        ..warn(
          '''shorebird preview will not work for releases created with "--no-codesign". However, you can still preview your app by signing the generated .xcarchive in Xcode.''',
        )
        ..warn(
          '''
When you distribute the .xcarchive in Xcode, you MUST uncheck "Manage Version and Build Number" in the Distribute App dialog.

If left checked, Xcode will rewrite the build number in the uploaded IPA, so the version that ships to App Store Connect will not match the version Shorebird recorded for this release. Patches will then fail to apply.''',
        );
    }

    String? splitDebugInfo;
    await runReleaseBuild((buildArgs, base64PublicKey) {
      splitDebugInfo = splitDebugInfoDirectory(buildArgs);
      return artifactBuilder.buildIpa(
        codesign: argResults.appleCodesign,
        flavor: flavor,
        target: target,
        args: buildArgs,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
      );
    });
    if (splitDebugInfo != null) warnIfDebugSymbolsHaveNoDwarf(splitDebugInfo!);

    final xcarchiveDirectory = artifactManager.getXcarchiveDirectory();
    if (xcarchiveDirectory == null) {
      throw CommandError(
        message:
            'Unable to find the .xcarchive directory in the iOS build '
            'output.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }

    final appDirectory = artifactManager.getIosAppDirectory(
      xcarchiveDirectory: xcarchiveDirectory,
    );

    if (appDirectory == null) {
      throw CommandError(
        message: 'Unable to find the .app directory in the .xcarchive.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }

    // Surface mismatched app extension versions here rather than letting the
    // user discover them via an App Store Connect rejection days later.
    // See https://github.com/shorebirdtech/shorebird/issues/1956.
    final versionMismatches = findAppExtensionVersionMismatches(
      appDirectory: appDirectory,
    );
    if (versionMismatches.isNotEmpty) {
      logger.warn(appExtensionVersionMismatchWarning(versionMismatches));
    }

    // When code signing is requested (the default), `flutter build ipa` is
    // expected to export a signed .ipa. Flutter treats the export step as
    // optional and exits 0 even when it fails (e.g. no signing certificate),
    // so we must verify the .ipa was actually produced. Otherwise we would
    // report a successful release and point the user at an .ipa that does not
    // exist. See https://github.com/shorebirdtech/shorebird/issues/3807.
    if (argResults.appleCodesign && artifactManager.getIpa() == null) {
      throw CommandError(
        message:
            '`flutter build ipa` exported no .ipa, usually because code '
            'signing failed. The build output above has the cause.',
        hint:
            'To sign the .xcarchive in Xcode instead, release it unsigned. '
            'Run: shorebird release ios --no-codesign',
        exitCode: ExitCode.software,
      );
    }

    return xcarchiveDirectory;
  }

  /// Warns when the `--split-debug-info` dSYM in [directory] has no
  /// `__debug_info`. It is still a valid dSYM with a matching UUID, so symbol
  /// uploads succeed, but Dart frames in crash reports have no names.
  ///
  /// Xcode 27's linker writes no debug map for Dart's snapshot on Flutter
  /// versions whose Dart emits an empty `DW_AT_comp_dir`, so dsymutil makes
  /// a dSYM with no DWARF. See
  /// https://github.com/shorebirdtech/shorebird/issues/4270.
  @visibleForTesting
  void warnIfDebugSymbolsHaveNoDwarf(String directory) {
    final symbolsFile = File(
      p.join(
        projectRoot.path,
        directory,
        ApplePatcherMixin.splitDebugInfoFileName,
      ),
    );
    // Flutter versions before the Mach-O dSYM write an ELF here, which
    // debugInfoSize returns null for.
    if (!symbolsFile.existsSync()) return;
    if (MachO.debugInfoSize(symbolsFile) != 0) return;
    logger.warn(
      '''
${p.relative(symbolsFile.path, from: projectRoot.path)} has no Dart debug info (no __debug_info section), so Dart frames in this release's crash reports will have no function names.

The likely cause is Xcode 27's linker with a Flutter version that doesn't support it yet. To get Dart symbols, run `flutter clean` and build the release with Xcode 26. https://github.com/shorebirdtech/shorebird/issues/4270 tracks the fix.''',
    );
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async => readReleaseVersionFromInfoPlist(
    File(p.join(releaseArtifactRoot.path, 'Info.plist')),
    hint: 'Re-run with --verbose to see the build output.',
  );

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final xcarchiveDirectory = artifactManager.getXcarchiveDirectory()!;
    await codePushClientWrapper.createIosReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      xcarchivePath: xcarchiveDirectory.path,
      runnerPath: artifactManager
          .getIosAppDirectory(xcarchiveDirectory: xcarchiveDirectory)!
          .path,
      isCodesigned: argResults.appleCodesign,
      podfileLockHash: shorebirdEnv.iosPodfileLockHash,
      signing: signing,
    );
  }

  @override
  String get postReleaseInstructions {
    final relativeArchivePath = p.relative(
      artifactManager.getXcarchiveDirectory()!.path,
    );
    if (argResults.appleCodesign) {
      const ipaSearchString = 'build/ios/ipa/*.ipa';
      return '''

Your next step is to upload your app to App Store Connect.

To upload to the App Store, do one of the following:
    1. Open ${lightCyan.wrap(relativeArchivePath)} in Xcode and use the "Distribute App" flow.
    2. Drag and drop the ${lightCyan.wrap(ipaSearchString)} bundle into the Apple Transporter macOS app (https://apps.apple.com/us/app/transporter/id1450874784).
    3. Run ${lightCyan.wrap('xcrun altool --upload-app --type ios -f $ipaSearchString --apiKey your_api_key --apiIssuer your_issuer_id')}.
       See "man altool" for details about how to authenticate with the App Store Connect API key.
''';
    } else {
      return '''

Your next step is to submit the archive at ${lightCyan.wrap(relativeArchivePath)} to the App Store using Xcode.

You can open the archive in Xcode by running:
    ${lightCyan.wrap('open $relativeArchivePath')}

${styleBold.wrap('Make sure to uncheck "Manage Version and Build Number" in the Distribute App dialog.')}
If left checked, Xcode will rewrite the build number in the uploaded IPA, so the version that ships will not match the one Shorebird recorded for this release, and patches will fail to apply.
''';
    }
  }
}
