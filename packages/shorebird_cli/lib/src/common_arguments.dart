import 'package:shorebird_cli/src/platform/platform.dart';

/// {@template argument_describer}
/// A class that describes an argument from a command/sub command.
/// {@endtemplate}
class ArgumentDescriber {
  /// {@macro argument_describer}
  const ArgumentDescriber({
    required this.name,
    required this.description,
    this.defaultValue,
  });

  /// Argument name as how the user writes it.
  final String name;

  /// Argument description that will be shown in the help of the command.
  final String description;

  /// Default value for this argument. Only provide this if the default value
  /// holds across all commands.
  final String? defaultValue;
}

/// Example value for `--release-version` in help and error messages.
const releaseVersionExample = '1.0.0+1';

/// A class that houses the name of arguments that are shared between different
/// commands and layers.
class CommonArguments {
  /// The Flutter --build-name argument.
  static const buildNameArg = ArgumentDescriber(
    name: 'build-name',
    description: '''
A "x.y.z" string used as the version number shown to users.
For each new version of your app, you will provide a version number to differentiate it
from previous versions.
On Android it is used as "versionName".
On Xcode builds it is used as "CFBundleShortVersionString".
On Windows it is used as the major, minor, and patch parts of the product and file
versions.''',
  );

  /// The Flutter --build-number argument.
  static const buildNumberArg = ArgumentDescriber(
    name: 'build-number',
    description: '''
An identifier used as an internal version number.
Each build must have a unique identifier to differentiate it from previous builds.
It is used to determine whether one build is more recent than another, with higher numbers indicating more recent build.
On Android it is used as "versionCode".
On Xcode builds it is used as "CFBundleVersion".''',
    defaultValue: '1.0',
  );

  /// A multioption argument that defines constants for the built application.
  /// These are forwarded to Flutter.
  static const dartDefineArg = ArgumentDescriber(
    name: 'dart-define',
    description: '''
Additional key-value pairs that will be available as constants from the String.fromEnvironment, bool.fromEnvironment, and int.fromEnvironment constructors.
Multiple defines can be passed by repeating "--dart-define" multiple times.''',
  );

  /// A multioption argument that specifies a file containing constants for the
  /// built application. These are forwarded to Flutter.
  static const dartDefineFromFileArg = ArgumentDescriber(
    name: 'dart-define-from-file',
    description: '''
The path of a .json or .env file containing key-value pairs that will be available as environment variables.
These can be accessed using the String.fromEnvironment, bool.fromEnvironment, and int.fromEnvironment constructors.
Multiple defines can be passed by repeating "--dart-define-from-file" multiple times.
Entries from "--dart-define" with identical keys take precedence over entries from these files.''',
  );

  /// A multioption argument that allows the user to specify an [ExportMethod].
  static const exportMethodArg = ArgumentDescriber(
    name: 'export-method',
    description: 'Specify how the IPA will be distributed (iOS only).',
  );

  /// An iOS-specific argument that allows the user to provide an export options
  /// plist, which is used by Xcode when packaging an IPA.
  static const exportOptionsPlistArg = ArgumentDescriber(
    name: 'export-options-plist',
    description:
        '''Export an IPA with these options. See "xcodebuild -h" for available exportOptionsPlist keys (iOS only).''',
  );

  /// An argument that allows the user to specify a Shorebird app ID directly,
  /// bypassing the app ID in shorebird.yaml.
  static const appIdArg = ArgumentDescriber(
    name: 'app-id',
    description:
        'The Shorebird app ID to use. Overrides the app ID in '
        'shorebird.yaml (e.g. "your-app-id").',
  );

  /// An argument that allows the user to specify a build flavor. You will most
  /// likely want to provide a custom description for this argument that more
  /// thoroughly explains what the flavor is used for.
  static const flavorArg = ArgumentDescriber(
    name: 'flavor',
    description: 'The app flavor',
  );

  /// An argument that allows the user to specify a public key file that will be
  /// used to validate patch signatures.
  static const publicKeyArg = ArgumentDescriber(
    name: 'public-key-path',
    description: '''
The path for a public key .pem file that will be used to validate patch signatures.
''',
  );

  /// Whether a release signs its patches. On by default: with no key of the
  /// customer's, the build embeds a key Shorebird manages.
  static const patchSigningArg = ArgumentDescriber(
    name: 'patch-signing',
    description: '''
Sign every patch to this release, so apps install only patches signed with its key.
On by default: the build embeds a key Shorebird manages for your organization.
To sign patches with your own key, pass --public-key-path or --public-key-cmd.
--no-patch-signing builds a release whose patches are unsigned.''',
  );

  /// An argument that allows the user to specify a private key file that will
  /// be used to sign the patch artifact.
  static const privateKeyArg = ArgumentDescriber(
    name: 'private-key-path',
    description: '''
The path for a private key .pem file that will be used to sign the patch artifact.
''',
  );

  /// An argument that allows the user to specify a command that outputs a
  /// PEM-encoded public key to stdout.
  static const publicKeyCmd = ArgumentDescriber(
    name: 'public-key-cmd',
    description: '''
Command that outputs a PEM-encoded public key to stdout for patch signature validation.
''',
  );

  /// An argument that allows the user to specify a command that signs data.
  /// The command reads data from stdin and outputs a base64 signature to
  /// stdout.
  static const signCmd = ArgumentDescriber(
    name: 'sign-cmd',
    description: '''
Command that reads data from stdin and outputs a base64 signature to stdout.
''',
  );

  /// An argument that allows the user to specify a release version. You will
  /// most likely want to provide a custom description for this argument that
  /// more thoroughly explains what the release version is used for.
  static const releaseVersionArg = ArgumentDescriber(
    name: 'release-version',
    description: 'The version of the release (e.g. "$releaseVersionExample").',
  );

  /// An argument that identifies a patch by its number within a release.
  static const patchNumberArg = ArgumentDescriber(
    name: 'patch-number',
    description: 'The number of the patch (e.g. "1").',
  );

  /// An argument that identifies an organization by its id.
  static const orgIdArg = ArgumentDescriber(
    name: 'org-id',
    description: 'The id of the organization (e.g. "42").',
  );

  /// Widens a command from one organization to every organization in the
  /// user's enterprise. An account is in at most one enterprise, so the flag
  /// takes no id.
  static const enterpriseArg = ArgumentDescriber(
    name: 'enterprise',
    description: 'Act on every organization in your enterprise.',
  );

  /// Help text for release version arguments in patch commands, where the
  /// version identifies which release the patch belongs to.
  static const patchReleaseVersionDescription =
      'The version of the release the patch belongs to '
      '(e.g. "$releaseVersionExample").';

  /// The Flutter --obfuscate argument.
  static const obfuscateArg = ArgumentDescriber(
    name: 'obfuscate',
    description:
        'In a release build, this flag removes identifiers and replaces '
        'them with randomized values for the purposes of source code '
        'obfuscation. This flag must always be combined with '
        '"--split-debug-info" command, to not break crash reports.',
  );

  /// An argument that allows the user to specify a directory where program
  /// symbols are stored.
  static const splitDebugInfoArg = ArgumentDescriber(
    name: 'split-debug-info',
    description: '''
In a release build, this flag reduces application size by storing Dart program symbols in a separate file on the host rather than
in the application. The value of the flag should be a directory where program symbol files can be stored for later use. These
symbol files contain the information needed to symbolize Dart stack traces. For an app built with this flag, the "flutter
symbolize" command with the right program symbol file is required to obtain a human readable stack trace.
''',
  );

  /// Maximum character length for an app display name.
  static const appDisplayNameMaxLength = 128;

  /// Maximum character length for a track name.
  static const trackNameMaxLength = 128;

  /// Checks a user-supplied name (an app display name, channel or track),
  /// returning why it is invalid, or null if it is fine.
  ///
  /// A name that is empty or only whitespace is rejected, as is one longer
  /// than [maxLength] characters. [label] names the value in the message,
  /// e.g. "Channel name".
  static String? nameError({
    required String label,
    required String value,
    required int maxLength,
  }) {
    if (value.trim().isEmpty) return '$label must not be blank.';
    if (value.length > maxLength) {
      return '$label must be at most $maxLength characters '
          '(got ${value.length}).';
    }
    return null;
  }

  /// The Dynamic Dispatch table cascade byte threshold, shared by
  /// `shorebird release` (forwarded to the Flutter build) and
  /// `shorebird patch` (forwarded to the linker).
  ///
  /// Hidden from `--help` on both commands: changing it off the default is
  /// almost never the right call for end users. It exists for internal
  /// testing of the cascade limiter.
  static const ddMaxBytesArg = ArgumentDescriber(
    name: 'dd-max-bytes',
    description:
        'Dynamic Dispatch table cascade byte threshold. '
        'Functions whose transitive caller tree exceeds this many bytes '
        'are routed through the indirect dispatch table. '
        'Set to 0 to disable.',
  );

  /// Accepted and ignored on `release` and `patch`. `--no-confirm` was a
  /// documented flag from 1.5.4 to 1.6.83, and the docs told CI scripts to
  /// pass it. Neither command asks for confirmation any more. `--confirm`,
  /// which asked for a prompt, stays an error.
  static const noConfirmArg = ArgumentDescriber(
    name: 'no-confirm',
    description: 'Does nothing. Kept so existing scripts keep working.',
  );

  /// Minimum valid value for [minLinkPercentage].
  static const minLinkPercentageMin = 0;

  /// Maximum valid value for [minLinkPercentage].
  static const minLinkPercentageMax = 100;

  /// An argument that allows the user to specify a minimum link percentage
  /// threshold.
  static const minLinkPercentage = ArgumentDescriber(
    name: 'min-link-percentage',
    defaultValue: '0',
    description:
        '''
The minimum link percentage ($minLinkPercentageMin-$minLinkPercentageMax) required in order to generate a patch (Apple platforms only).

Patches with a lower link percentage than what is provided here will fail.
''',
  );
}
