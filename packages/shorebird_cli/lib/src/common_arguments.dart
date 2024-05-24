class ArgumentDescriber {
  const ArgumentDescriber({
    required this.name,
    required this.description,
  });

  final String name;
  final String description;
}

/// A class that houses the name of arguments that are shared between different
/// commands and layers.
class CommonArguments {
  static const publicKeyArg = ArgumentDescriber(
    name: 'public-key-path',
    description: '''
The path for a public key file that will be used to validate patch signatures.
''',
  );

  static const privateKeyArg = ArgumentDescriber(
    name: 'private-key-path',
    description: '''
The path for a private key file that will be used to sign the patch artifact.
''',
  );
}
