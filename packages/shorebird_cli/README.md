# Shorebird CLI

**🚧 This project is under heavy development 🚧**

**❗️ Currently, only Android arm64 release builds are supported but we are working on expanding to other platforms/architectures.**

The Shorebird command-line allows developers to interact with various Shorebird services. We're currently focusing on CodePush but the Shorebird CLI will continue to expand as we add more capabilities.

## Installing

```sh
dart pub global activate --source git https://github.com/shorebirdtech/shorebird --git-path packages/shorebird_cli
```

## Commands

### Init

Get started by initializing shorebird in your current project.

```bash
shorebird init
```

**Sample**

```
shorebird init
✓ Initialized Shorebird (27ms)

🐦 Shorebird initialized successfully!

✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.

Reference the following commands to get started:

🚙 To run your project use: "shorebird run".
📦 To build your project use: "shorebird build".
🚀 To publish a new update use: "shorebird publish".

For more information, visit https://shorebird.dev
```

### Login

Request an API key and use `shorebird login` to authenticate:

```bash
shorebird login
```

**Sample**

```
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

```
shorebird logout
✓ Logging out of shorebird.dev (1ms)
```

### Create App

To create an app use the `shorebird apps create` command. An app-id can be specified as a CLI option but shorebird will default to the product_id defined in the `shorebird.yaml`

```bash
# Create an app using default app id
shorebird apps create

# Create an app using an explicit app id
shorebird apps create --app-id "my-app-id"
```

**Sample**

```
shorebird apps create
? Enter the App ID (default-id) my-app-id
Created new app: my-app-id
```

### Delete App

To delete an existing app on Shorebird, use the `shorebird apps delete` command. An app-id can be specified as a CLI option but shorebird will default to the product_id defined in the `shorebird.yaml`

```bash
# Create an app using default app id
shorebird apps delete

# Create an app using an explicit app id
shorebird apps delete --app-id "my-app-id"
```

**Sample**

```
shorebird apps delete
? Enter the App ID (default-id) my-app-id
Deleting an app is permanent. Continue? (y/N) Yes
Deleted app: my-app-id
```

### List Apps

List all existing apps in Shorebird using the `shorebird apps list` command:

```bash
shorebird apps list
```

**Sample**

```
shorebird apps list
my-counter: v1.0.0 (patch #1)
my-example: v2.1.0 (patch #2)
```

### Run

Run an existing application using the Shorebird Engine via the `shorebird run` command:

```bash
shorebird run
```

**❗️Note**: If it's the first time using shorebird, `shorebird run` will download and build the shorebird engine which may take some time. The shorebird engine will be cached for subsequent runs.

### Build

Build a new release of your application using the `shorebird build` command:

```bash
shorebird build
```

**❗️Note**: If it's the first time using shorebird, `shorebird build` will download and build the shorebird engine which may take some time. The shorebird engine will be cached for subsequent runs.

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
  apps      Manage your Shorebird apps.
  build     Build a new release of your application.
  init      Initialize Shorebird.
  login     Login as a new Shorebird user.
  logout    Logout of the current Shorebird user
  publish   Publish an update.
  run       Run the Flutter application.
  update    Update the CLI.

Run "shorebird help <command>" for more information about a command.
```
