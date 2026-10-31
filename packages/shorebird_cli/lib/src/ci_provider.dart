/// The CI service [environment] says the CLI is running on, such as
/// `github-actions`, `other` for a CI that sets only a generic variable such
/// as `CI`, or null when not on CI.
///
/// Names follow npm's `ci-info` package, which npm sends in its `User-Agent`
/// as `ci/<name>`. Specific services come before the generic variables, since
/// most services also set `CI`.
String? ciProvider(Map<String, String> environment) {
  bool has(String name) => environment.containsKey(name);

  // https://docs.github.com/en/actions/reference/variables-reference
  if (has('GITHUB_ACTIONS')) return 'github-actions';
  // https://docs.codemagic.io/yaml-basic-configuration/environment-variables/
  if (has('CM_BUILD_ID')) return 'codemagic';
  // https://devcenter.bitrise.io/en/references/available-environment-variables.html
  if (has('BITRISE_IO')) return 'bitrise';
  // https://docs.gitlab.com/ci/variables/predefined_variables/
  if (has('GITLAB_CI')) return 'gitlab';
  // https://circleci.com/docs/variables/
  if (has('CIRCLECI')) return 'circleci';
  // https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables
  if (has('TF_BUILD')) return 'azure-pipelines';
  // https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#using-environment-variables
  if (has('JENKINS_URL')) return 'jenkins';
  // https://buildkite.com/docs/pipelines/configure/environment-variables
  if (has('BUILDKITE')) return 'buildkite';
  // https://support.atlassian.com/bitbucket-cloud/docs/variables-and-secrets/
  if (has('BITBUCKET_BUILD_NUMBER')) return 'bitbucket';
  // https://developer.apple.com/documentation/xcode/environment-variable-reference
  if (has('CI_XCODE_PROJECT')) return 'xcode-cloud';
  // https://docs.travis-ci.com/user/environment-variables/#default-environment-variables
  if (environment['TRAVIS'] == 'true') return 'travis';
  // https://www.appveyor.com/docs/environment-variables/
  if (has('APPVEYOR')) return 'appveyor';
  // https://cirrus-ci.org/guide/writing-tasks/#environment-variables
  if (has('CIRRUS_CI')) return 'cirrus';
  // https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-env-vars.html
  if (has('AWS_REGION') && has('CODEBUILD_INITIATOR')) return 'codebuild';
  if (environment['BOT'] == 'true' ||
      environment['CONTINUOUS_INTEGRATION'] == 'true' ||
      has('CI')) {
    return 'other';
  }
  return null;
}
