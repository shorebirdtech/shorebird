import 'package:path/path.dart' as p;

/// Candidate paths for codecov config files.
///
/// See https://docs.codecov.com/docs/codecov-yaml#can-i-name-the-file-codecovyml
final codecovFileNames = {
  'codecov.yml',
  '.codecov.yml',
  p.join('.github', 'codecov.yml'),
  p.join('.github', '.codecov.yml'),
  p.join('dev', 'codecov.yml'),
  p.join('dev', '.codecov.yml'),
};
