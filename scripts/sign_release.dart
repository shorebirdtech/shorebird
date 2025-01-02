import 'dart:io';

const keyPropertiesDefinition = '''
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
''';

const signingConfigsDefinition = '''
signingConfigs {
       release {
           storeFile file(System.getenv("KEYSTORE_FILE") ?: keystoreProperties['storeFile'])
           keyAlias System.getenv("KEYSTORE_ALIAS") ?: keystoreProperties['keyAlias']
           keyPassword System.getenv("KEYSTORE_PASSWORD") ?: keystoreProperties['keyPassword']
           storePassword System.getenv("KEYSTORE_PASSWORD") ?: keystoreProperties['storePassword']
       }
   }
''';

void main() {
  final buildGradle = File('./android/app/build.gradle');
  if (!buildGradle.existsSync()) {
    throw Exception('Unable to locate build.gradle.');
  }

  final lines = buildGradle.readAsLinesSync();

  final androidBlock = lines.skipWhile((line) => !line.contains('android {'));
  final androidBlockIndex = lines.indexOf(androidBlock.first);
  lines.insert(androidBlockIndex, keyPropertiesDefinition);

  final buildTypesBlock = lines.skipWhile(
    (line) => !line.contains('buildTypes {'),
  );
  final buildTypesBlockIndex = lines.indexOf(buildTypesBlock.first);
  lines.insert(buildTypesBlockIndex, signingConfigsDefinition);

  final signingConfigLine = lines.indexWhere(
    (line) => line.contains('signingConfig = signingConfigs.debug'),
  );
  lines[signingConfigLine] = lines[signingConfigLine].replaceFirst(
    'signingConfigs.debug',
    'signingConfigs.release',
  );

  buildGradle.writeAsStringSync(lines.join('\n'));
}
