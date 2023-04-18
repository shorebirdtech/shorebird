# Shorebird CLI

**🚧 This project is under heavy development 🚧**

**❗️ Currently, only Android arm64 release builds are supported but we are working on expanding to other platforms/architectures.**

The Shorebird command-line allows developers to interact with various Shorebird services. We're currently focusing on CodePush but the Shorebird CLI will continue to expand as we add more capabilities.

## Installing

```
curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | sh
```

## Commands

### Init

Get started by initializing shorebird in your current project.

```bash
# 1. Creates a new app (if one doesn't exist) with a stable channel.
# 2. Generates a shorebird.yaml (if one doesn't exist).
# 3. Adds the shorebird.yaml to the pubspec.yaml flutter assets.
shorebird init
```

**Sample**

```
shorebird init
✓ Initialized Shorebird (27ms)

🐦 Shorebird initialized successfully!

✅ A shorebird app has been created.
✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.

Reference the following commands to get started:

🚙 To run your project use: "shorebird run".
📦 To build your project use: "shorebird build".
🚀 To push a new update use: "shorebird patch".

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

### Account

To see information about your Shorebird account, use the `shorebird account` command.

```bash
shorebird account
```

**Sample**

```
$ shorebird account
You are logged in as <bryan@shorebird.dev>
```

### Doctor

To check your environment for common issues, use the `shorebird doctor` command.

```bash
shorebird doctor
```

**Sample**

```
$ shorebird doctor

Shorebird v0.0.3

✓ Shorebird is up-to-date (0.7s)
✓ Flutter install is correct (0.1s)
✓ AndroidManifest.xml files contain INTERNET permission (26ms)

No issues detected!
```

### Create App

To create an app use the `shorebird apps create` command. An app id can be specified as a CLI option but shorebird will default to the `app_id` defined in the `shorebird.yaml`

```bash
# Create an app using default app id
shorebird apps create

# Create an app using an explicit app id
shorebird apps create --app-id "my-app-id"
```

**Sample**

```
shorebird apps create
? Enter the App ID (default_id) my_app_id
Created new app: my_app_id
```

### Delete App

To delete an existing app on Shorebird, use the `shorebird apps delete` command. An app-id can be specified as a CLI option but shorebird will default to the app_id defined in the `shorebird.yaml`

```bash
# Create an app using default app id
shorebird apps delete

# Create an app using an explicit app id
shorebird apps delete --app-id "my-app-id"
```

**Sample**

```
shorebird apps delete
? Enter the App ID (default_id) my_app_id
Deleting an app is permanent. Continue? (y/N) Yes
Deleted app: my_app_id
```

### List Apps

List all existing apps in Shorebird using the `shorebird apps list` command:

```bash
shorebird apps list
```

**Sample**

```
shorebird apps list
📱 Apps
┌───────────────────┬──────────────────────────────────────┬─────────┬───────┐
│ Name              │ ID                                   │ Release │ Patch │
├───────────────────┼──────────────────────────────────────┼─────────┼───────┤
│ Shorebird Counter │ 30370f27-dbf1-4673-8b20-fb096e38dffa │ 1.0.0   │ 1     │
├───────────────────┼──────────────────────────────────────┼─────────┼───────┤
│ Shorebird Clock   │ 05b45471-a5f3-48cd-b26a-da29d95914a7 │ --      │ --    │
└───────────────────┴──────────────────────────────────────┴─────────┴───────┘
```

### Run

Run an existing application using the Shorebird Engine via the `shorebird run` command:

```bash
shorebird run
```

**❗️Note**: If it's the first time using shorebird, `shorebird run` will download and build the shorebird engine which may take some time. The shorebird engine will be cached for subsequent runs.

### Release

Builds and submits your app to Shorebird. Shorebird saves the compiled Dart code from your application in order to make smaller updates to your app.

```bash
# 1. Generate a release build.
# 2. Create a release in Shorebird
# 3. Upload the release artifact to Shorebird.
shorebird release
```

**Sample**

```
$ shorebird release
✓ Building release (5.1s)
✓ Fetching apps (0.2s)

What is the version of this release? (1.0.0) 1.0.0

🚀 Ready to create a new release!

📱 App: My App (30370f27-dbf1-4673-8b20-fb096e38dffa)
📦 Release Version: 1.0.0
🕹️ Platform: android (arm64, arm32, x86)

Would you like to continue? (y/N) Yes
✓ Fetching releases (55ms)
✓ Creating release (45ms)
✓ Creating artifacts (4.6s)

✅ Published Release!

Your next step is to upload the app bundle to the Play Store.
./build/app/outputs/bundle/release/app-release.aab

See the following link for more information:
https://support.google.com/googleplay/android-developer/answer/9859152?hl=en
```

### Patch

The patch command allows developers to upload new patches (updates) of their Flutter application to the Shorebird CodePush API. These updates are then pushed directly to users' devices.

```bash
# Publish the artifacts
# 1. Builds the artifacts (equivalent to a shorebird build)
# 2. Creates a new patch if one does not exist
# 3. Uploads the artifacts as part of the patch
# 4. Promotes the patch to the "stable" channel
shorebird patch
```

**Sample**

```
shorebird patch
✓ Building patch (16.2s)
✓ Fetching apps (0.1s)

Which release is this patch for? (0.1.0) 0.1.0

🚀 Ready to publish a new patch!

📱 App: My App (61fc9c16)
📦 Release Version: 0.1.0
📺 Channel: stable
🕹️ Platform: android (arm64, arm32, x86)

Would you like to continue? (y/N) Yes
✓ Fetching release (41ms)
✓ Fetching release artifacts (43ms)
✓ Downloading release artifacts (0.2s)
✓ Creating artifacts (0.3s)
✓ Uploading artifacts (43ms)
✓ Fetching channels (40ms)
✓ Promoting patch to stable (43ms)

✅ Published Patch!
```

### Build

Build a new release of your application using the `shorebird build` command:

```bash
# Build an AppBundle
shorebird build appbundle

# Build an APK
shorebird build apk
```

### List Channels

See all available channels for your application using the `shorebird channels list` command:

```bash
shorebird channels list
```

**Sample**

```
shorebird channels list
📱 App ID: 61fc9c16-3c4a-4825-a155-9765993614aa
📺 Channels
┌─────────────┐
│ Name        │
├─────────────┤
│ stable      │
├─────────────┤
│ development │
└─────────────┘
```

### Create Channels

Create a new channel for your application using the `shorebird channels create` command:

```bash
shorebird channels create --name MyChannel
```

**Sample**

```
shorebird channels create --name MyChannel

🚀 Ready to create a new channel!

📱 App ID: 485df03f-f522-4242-bf3d-31c0869bacac
📺 Channel: MyChannel

Would you like to continue? (y/N) Yes
✓ Creating channel (0.2s)

✅ New Channel Created!
```

### Cancel Subscription

Cancel your Shorebird subscription using `shorebird subscription cancel` command:

```bash
shoreburd subscription cancel
```

**Sample**

```bash
$ shorebird subscription cancel
This will cancel your Shorebird subscription. Are you sure? (y/N) Yes
Your subscription has been canceled.
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
  apps       Manage your Shorebird apps.
  build      Build a new release of your application.
  channels   Manage the channels for your Shorebird app.
  doctor     Show information about the installed tooling.
  init       Initialize Shorebird.
  login      Login as a new Shorebird user.
  logout     Logout of the current Shorebird user
  patch      Publish new patches for a specific release to Shorebird.
  release    Builds and submits your app to Shorebird.
  run        Run the Flutter application.
  upgrade    Upgrade your copy of Shorebird.

Run "shorebird help <command>" for more information about a command.
```
