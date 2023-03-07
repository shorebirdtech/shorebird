# Shorebird CLI

**🚧 This project is under heavy development 🚧**

**❗️ Currently, only Android arm64 release builds are supported but we are working on expanding to other platforms/architectures.**

The Shorebird command-line allows developers to interact with various Shorebird services. We're currently focusing on CodePush but the Shorebird CLI will continue to expand as we add more capabilities.

## Installing

```sh
dart pub global activate --source git https://github.com/shorebirdtech/shorebird --git-path packages/shorebird_cli
```

## Commands

### Login

Get started by requesting an API key and using `shorebird login` to authenticate:

```bash
shorebird login
```

**Sample**

```bash
shorebird login
? Please enter your API Key: <API-KEY>
✓ Logging into shorebird.dev (7ms)
You are now logged in.
```

### Logout

To sign out and remove an existing session, use the `shorebird logout` command:

```bash
shorebird logout
```

**Sample**

```bash
shorebird logout
✓ Logging out of shorebird.dev (1ms)
```

### Run

Run an existing application using the Shorebird Engine via the `shorebird run` command:

```bash
shorebird run
```

**❗️Note**: If it's the first time, `shorebird run` will download and build the shorebird engine which may take some time. The shorebird engine will be cached for subsequent runs.

### Build

Build a new release of your application using the `shorebird build` command:

```bash
shorebird build
```

### Publish

The publish command allows developers to publish new releases of their Flutter application to the Shorebird CodePush API. These updates are then pushed directly to users' devices.

```bash
# Publish the default release
shorebird publish

# Publish a specific release
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
  build     Build a new release of your application.
  login     Login as a new Shorebird user.
  logout    Logout of the current Shorebird user
  publish   Publish an update.
  run       Run the Flutter application.
  update    Update the CLI.

Run "shorebird help <command>" for more information about a command.
```
