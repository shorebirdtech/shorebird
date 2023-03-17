## Glossary

Before getting started, we recommend familiarizing yourslef with the following terms and their definitions within the Shorebird ecosystem.

### App

**Definition**

The application downloaded and run on various devices/platforms. All applications must have an `app_id` which uniquely identifies them in Shorebird.

**Example**

The [`time_shift`](https://github.com/shorebirdtech/time_shift) app is an example of an application. The corresponding `app_id` can be found in the `shorebird.yaml` file at the root of the project.

### Release

**Definition**

A release build of an application that is distributed to devices. A release can have zero or more patches applied to it.

**Example**

When we run a `shorebird build ...` or `flutter build ...` we are creating a release build which can be distributed to user's devices (usually via app stores). A release refers to a specific version of an application running on a device and is always associated with a release version (e.g. `1.0.0`).

### Patch

**Definition**

An over the air update which is applied to a specific release. All patches have a patch number (auto-incrementing integer) and multiple patches can be published for a given app release version.

**Example**

If we had an existing `1.0.0` release of `time_shift` available, we could publish a patch to `version 1.0.0`. This would result in "patch #1", there can be many patches to a given release, typically the latest is active and applied to devices in the field.

### Channel

**Definition**

A tag used to manage the subset of applications that receive a patch. By default, a "stable" channel is created and used by devices to query for available patches.

**Example**

We can create a "development" and "staging" channels in addition to the "stable" channel and promote patches to those internal channels for testing before rolling them out to the general public.

### Artifact

**Definition**

An artifact contains metadata about the contents of a specific patch for a specific platform and architecture.

**Example**

Once a new patch is published, on the next launch the application will be notified of the new available patch and will download the artifact associated with that patch for the specific platform and architecture (e.g. 'android', 'aarm64').
