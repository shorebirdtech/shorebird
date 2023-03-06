## Shorebird CLI

**🚧 This project is under heavy development 🚧**

The Shorebird command-line allows developers to interact with various Shorebird services. We're currently focusing on CodePush but the Shorebird CLI will continue to expand as we add more capabilities.

### Installing 🧑‍💻

```sh
dart pub global activate --source git https://github.com/shorebirdtech/shorebird --git-path packages/shorebird_cli
```

## Publish

The publish command allows developers to publish new releases of their Flutter application to the Shorebird CodePush API. These updates are then pushed directly to users' devices.

```
shorebird publish <path/to/libapp.so>
```

### Usage

```
The shorebird command-line tool

Usage: shorebird <command> [arguments]

Global options:
-h, --help            Print this usage information.
-v, --version         Print the current version.
    --[no-]verbose    Noisy logging, including all shell commands executed.

Available commands:
  publish   Publish an update.
  update    Update the CLI.

Run "shorebird help <command>" for more information about a command.
```
