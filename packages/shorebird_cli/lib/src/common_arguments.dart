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

  /// An argument that allows the user to specify a private key file that will
  /// be used to sign the patch artifact.
  static const privateKeyArg = ArgumentDescriber(
    name: 'private-key-path',
    description: '''
The path for a private key .pem file that will be used to sign the patch artifact.
''',
  );

  /// An argument that allows the user to specify a release version. You will
  /// most likely want to provide a custom description for this argument that
  /// more thoroughly explains what the release version is used for.
  static const releaseVersionArg = ArgumentDescriber(
    name: 'release-version',
    description: 'The version of the release (e.g. "1.0.0").',
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

  /// An argument that allows the user to specify a minimum link percentage
  /// threshold.
  static const minLinkPercentage = ArgumentDescriber(
    name: 'min-link-percentage',
    defaultValue: '0',
    description: '''
The minimum link percentage (0-100) required in order to generate a patch (Apple platforms only).

Patches with a lower link percentage than what is provided here will fail.
''',
  );
}
