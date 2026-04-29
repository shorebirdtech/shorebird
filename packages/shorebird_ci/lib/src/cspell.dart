import 'package:path/path.dart' as p;

/// Candidate paths for cSpell config files.
///
/// See https://cspell.org/docs/getting-started#1-create-a-configuration-file
final cSpellConfigFileNames = {
  '.cspell.json',
  'cspell.json',
  '.cSpell.json',
  'cSpell.json',
  '.cspell.jsonc',
  'cspell.jsonc',
  '.cspell.yaml',
  'cspell.yaml',
  '.cspell.yml',
  'cspell.yml',
  '.cspell.config.json',
  'cspell.config.json',
  '.cspell.config.jsonc',
  'cspell.config.jsonc',
  '.cspell.config.yaml',
  'cspell.config.yaml',
  '.cspell.config.yml',
  'cspell.config.yml',
  p.join('.config', '.cspell.json'),
  p.join('.config', 'cspell.json'),
  p.join('.config', 'cspell.yaml'),
  p.join('.config', 'cspell.yml'),
  p.join('.vscode', '.cspell.json'),
  p.join('.vscode', 'cSpell.json'),
  p.join('.vscode', 'cspell.json'),
};
