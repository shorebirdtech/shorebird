## Shorebird 🐦

[![Discord](https://dcbadge.vercel.app/api/server/9hKJcWGcaB)](https://discord.gg/9hKJcWGcaB)

[![ci](https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml/badge.svg)](https://github.com/shorebirdtech/shorebird/actions/workflows/main.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE-MIT)
[![License: Apache](https://img.shields.io/badge/license-Apache-orange.svg)](./LICENSE-APACHE)

Home of the Shorebird Tools

## Status

We're in the process of converting the quick demos written by one person, into a
multi-contributor project usable by others. Previous demo code can be found at:
https://github.com/shorebirdtech/old_repo

## Packages

This repository is a monorepo containing the following packages:

| Package                                                                             | Description                                                                             |
| ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| [shorebird_cli](packages/shorebird_cli/README.md)                                   | Command-line which allows developers to interact with various Shorebird services        |
| [shorebird_code_push_api](packages/shorebird_code_push_api/README.md)               | Server which exposes endpoints to support CodePush for Flutter applications             |
| [shorebird_code_push_api_client](packages/shorebird_code_push_api_client/README.md) | Dart library which allows Dart applications to interact with the ShoreBird CodePush API |
| [shorebird_code_push_updater](updater/README.md)                                    | Rust library which handles the CodePush logic and does the real update work             |

For more information, please refer to the documentation for each package.

**❗️ Note: This project is under heavy development. Things will change frequently and none of the code is ready for production use. We will do our best to keep the documentation up-to-date.**

## Contributing

If you're interested in contributing, please join us on
[Discord](https://discord.gg/9hKJcWGcaB).

## License

Shorebird projects are licensed for use under either Apache License, Version 2.0
(LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0) MIT license
(LICENSE-MIT or http://opensource.org/licenses/MIT) at your option.

See our license philosophy for more information on why we license files this
way:
https://github.com/shorebirdtech/handbook/blob/main/engineering.md#licensing-philosophy
