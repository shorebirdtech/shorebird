import 'package:shorebird_cli/src/ci_provider.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(ciProvider, () {
    test('returns null off CI', () {
      expect(ciProvider({}), isNull);
    });

    final cases = <Map<String, String>, String>{
      {'GITHUB_ACTIONS': 'true', 'CI': 'true'}: 'github-actions',
      {'CM_BUILD_ID': '1', 'CI': 'true'}: 'codemagic',
      {'BITRISE_IO': 'true', 'CI': 'true'}: 'bitrise',
      {'GITLAB_CI': 'true', 'CI': 'true'}: 'gitlab',
      {'CIRCLECI': 'true', 'CI': 'true'}: 'circleci',
      {'TF_BUILD': 'True'}: 'azure-pipelines',
      {'JENKINS_URL': 'https://ci.example.com'}: 'jenkins',
      {'BUILDKITE': 'true', 'CI': 'true'}: 'buildkite',
      {'BITBUCKET_BUILD_NUMBER': '1', 'CI': 'true'}: 'bitbucket',
      {'CI_XCODE_PROJECT': 'App.xcodeproj', 'CI': 'TRUE'}: 'xcode-cloud',
      {'TRAVIS': 'true', 'CI': 'true'}: 'travis',
      {'APPVEYOR': 'True'}: 'appveyor',
      {'CIRRUS_CI': 'true'}: 'cirrus',
      {'AWS_REGION': 'us-east-1', 'CODEBUILD_INITIATOR': 'x'}: 'codebuild',
      {'CI': ''}: 'other',
      {'BOT': 'true'}: 'other',
      {'CONTINUOUS_INTEGRATION': 'true'}: 'other',
    };
    for (final MapEntry(key: environment, value: name) in cases.entries) {
      test('returns $name for $environment', () {
        expect(ciProvider(environment), equals(name));
      });
    }

    test('ignores TRAVIS when it is not "true"', () {
      expect(ciProvider({'TRAVIS': 'false'}), isNull);
    });

    test('needs both AWS_REGION and CODEBUILD_INITIATOR for codebuild', () {
      expect(ciProvider({'AWS_REGION': 'us-east-1'}), isNull);
    });
  });
}
