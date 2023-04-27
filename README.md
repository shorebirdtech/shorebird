## Shorebird 🐦

[![Discord](https://dcbadge.vercel.app/api/server/9hKJcWGcaB)](https://discord.gg/9hKJcWGcaB)

[![ci](https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml/badge.svg)](https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml)
[![Nighty E2E](https://github.com/shorebirdtech/shorebird/actions/workflows/nightly_e2e.yaml/badge.svg)](https://github.com/shorebirdtech/shorebird/actions/workflows/nightly_e2e.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE-MIT)
[![License: Apache](https://img.shields.io/badge/license-Apache-orange.svg)](./LICENSE-APACHE)

Home of the Shorebird Tools

## Status

We're in the process of converting the quick demos written by one person, into a
multi-contributor project usable by others. Previous demo code can be found at:
https://github.com/shorebirdtech/old_repo

## Getting Started

Refer to [shorebird/install](https://github.com/shorebirdtech/install) for
installation instructions.

## Packages

This repository is a monorepo containing the following packages:

| Package                                                                         | Description                                                                             |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| [shorebird_cli](packages/shorebird_cli/README.md)                               | Command-line which allows developers to interact with various Shorebird services        |
| [shorebird_code_push_client](packages/shorebird_code_push_client/README.md)     | Dart library which allows Dart applications to interact with the ShoreBird CodePush API |
| [shorebird_code_push_protocol](packages/shorebird_code_push_protocol/README.md) | Dart library which contains common interfaces used by Shorebird CodePush                |
| [discord_gcp_alerts](packages/discord_gcp_alerts/README.md)                     | Dart server which forwards GCP alerts to Discord                                        |
| [jwt](packages/jwt/README.md)                                                   | Dart library for verifying Json Web Tokens                                              |
| [updater](updater/README.md)                                                    | Rust library which handles the CodePush logic and does the real update work             |

For more information, please refer to the documentation for each package.

**❗️ Note: This project is under heavy development. Things will change frequently and none of the code is ready for production use. We will do our best to keep the documentation up-to-date.**

## Contributing

If you're interested in contributing, please join us on
[Discord](https://discord.gg/9hKJcWGcaB).

### Environment setup

Working on Shorebird requires Dart and Rust.

We currently assume the Dart from the Flutter SDK on the 'stable' channel. Due
to the way the Dart compiler works, Shorebird requires an exact version of
Flutter/Dart to operate correctly today.

Once both are installed, `./scripts/bootstrap.sh` will run `pub get` all
packages in the repository.

### Running tests

We don't yet have a script to run tests locally. For now, you can run tests
manually by running `dart test` in a Dart package directory.

### Tracking coverage

The following command will generate a coverage report for the Dart packages:

```bash
dart test --coverage=coverage && dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --check-ignore
```

We don't yet have a recommended way to view the coverage report but there are
several extensions available in VSCode.

## License

Shorebird projects are licensed for use under either Apache License, Version 2.0
(LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0) MIT license
(LICENSE-MIT or http://opensource.org/licenses/MIT) at your option.

See our license philosophy for more information on why we license files this
way:
https://github.com/shorebirdtech/handbook/blob/main/engineering.md#licensing-philosophy
