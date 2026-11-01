## Shorebird 🐦

[![Discord](https://img.shields.io/discord/1030243211995791380?style=for-the-badge&logo=discord&color=blue)](https://discord.gg/shorebird)
<a href="https://www.producthunt.com/posts/shorebird-code-push?utm_source=badge-featured&utm_medium=badge&utm_souce=badge-shorebird&#0045;code&#0045;push" target="_blank"><img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=449946&theme=neutral" alt="Shorebird&#0032;Code&#0032;Push - Flutter&#0032;over&#0032;the&#0032;air&#0032;updates | Product Hunt" style="width: 128px; height: 27px;" width="128" height="27" /></a>

[![ci](https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml/badge.svg)](https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml)
[![e2e](https://github.com/shorebirdtech/shorebird/actions/workflows/e2e.yaml/badge.svg)](https://github.com/shorebirdtech/shorebird/actions/workflows/e2e.yaml)
[![codecov](https://codecov.io/gh/shorebirdtech/shorebird/branch/main/graph/badge.svg)](https://codecov.io/gh/shorebirdtech/shorebird)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE-MIT)
[![License: Apache](https://img.shields.io/badge/license-Apache-orange.svg)](./LICENSE-APACHE)

## Getting Started

Visit https://docs.shorebird.dev to get started.

## Packages

This repository is a monorepo containing the following packages:

| Package                                                                         | Description                                                                             |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| [shorebird_cli](packages/shorebird_cli/README.md)                               | Command-line which allows developers to interact with various Shorebird services        |
| [shorebird_code_push_client](packages/shorebird_code_push_client/README.md)     | Dart library which allows Dart applications to interact with the Shorebird CodePush API |
| [shorebird_code_push_protocol](packages/shorebird_code_push_protocol/README.md) | Dart library which contains common interfaces used by Shorebird CodePush                |
| [redis_client](packages/redis_client/README.md)                                 | Dart library for interacting with Redis                                                 |
| [scoped_deps](packages/scoped_deps/README.md)                                   | A simple dependency injection library built on Zones                                    |

For more information, please refer to the documentation for each package.

## Contributing

If you're interested in contributing, please join us on
[Discord](https://discord.gg/shorebird).

### Environment setup

Working on Shorebird requires Dart.

`./scripts/bootstrap.sh` will run `pub get` all packages in the repository.

### Running tests

`./tool/agent-verify.sh` runs format, analyze and test over every workspace
package, the way CI does, and skips each package whose inputs already passed.
A single package is `dart test` in that package's directory.

To generate a coverage report, install `lcov` and `very_good_cli`:

```
brew install lcov
dart pub global activate very_good_cli
```

Then run tests with the `--coverage` flag, from the packages directory:

```
very_good test -r --coverage
genhtml coverage/lcov.info -o coverage
```

(If you run it in the root, it will find packages in bin/cache/flutter and try
to run tests there, some of which will fail.)

You can view the generated coverage report via:

```
open coverage/index.html
```

### Tracking coverage

The following command will generate a coverage report for the Dart packages:

```bash
dart test --coverage=coverage && dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --check-ignore
```

Coverage reports are uploaded to [Codecov](https://app.codecov.io/gh/shorebirdtech/shorebird).

## License

Shorebird projects are licensed for use under either Apache License, Version 2.0
(LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0) MIT license
(LICENSE-MIT or http://opensource.org/licenses/MIT) at your option.

See our license philosophy for more information on why we license files this
way:
https://handbook.shorebird.dev/engineering/#licensing-philosophy
