import 'package:shorebird_cli/src/platform/ios.dart';

/// {@template argument_describer}
/// A class that describes an argument from a command/sub command.
/// {@endtemplate}
class ArgumentDescriber {
  const ArgumentDescriber({
    required this.name,
    required this.description,
  });

  /// Argument name as how the user writes it.
  final String name;

  /// Argument description that will be shown in the help of the command.
  final String description;
}

/// A class that houses the name of arguments that are shared between different
/// commands and layers.
class CommonArguments {
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

  static const publicKeyArg = ArgumentDescriber(
    name: 'public-key-path',
    description: '''
The path for a public key .pem file that will be used to validate patch signatures.
''',
  );

  static const privateKeyArg = ArgumentDescriber(
    name: 'private-key-path',
    description: '''
The path for a private key .pem file that will be used to sign the patch artifact.
''',
  );
}
