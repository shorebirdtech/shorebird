// cspell:words gradlew Phost
// ignore_for_file: avoid_print

// End-to-end test of an add-to-app module on Android, released once and
// patched once in two host apps: the real CLI against a real server, a real
// Flutter build, and both hosts run on an emulator.
//
// It makes a Flutter module and releases it as an AAR, then builds one native
// host project as two apps with different application IDs and versions, both
// embedding that AAR, and installs both. It patches the module once, then
// checks each host downloads and boots the patch, that host A updated to a new
// version keeps it, and what each host's updater sends.
//
// Usage: dart scripts/module_e2e.dart [--host-versions] [<flutter-version>]
//
//   <flutter-version>  Flutter version or commit to release and patch with.
//                      Default: the Flutter the CLI pins. The module and its
//                      hosts are created with the pinned one either way.
//   --host-versions    The Flutter keys a module's releases on each host's
//                      version, as every Flutter before module versions did:
//                      it doesn't bake --release-version into the module.
//                      Without it the Flutter is expected to bake it.
//
// Module versions (the default): the module is released as 1.0.0+1. Both
// hosts boot the patch, A keeps it once updated to a new version, and each
// host's patch check names the module's release_version, its own
// host_bundle_id, and its own version as host_version. Events carry the same
// three fields, read from the same config (updater events.rs); the updater's
// fixtures cover their encoding.
//
// Host versions (--host-versions): the module is released as host A's
// version. A boots the patch; B, a version with no release, keeps running
// what it shipped, as does A once updated to a version with no release.
//
// Prerequisites: those of boot_recovery_e2e.dart's android mode (the CLI's
// `shorebird` on PATH and signed in, a booted emulator adb sees, Java), and
// the Android SDK at ANDROID_HOME.

import 'dart:io';

import 'e2e_helpers.dart';

/// The module's own version, its release version when the Flutter bakes it.
const moduleVersion = '1.0.0+1';

/// The class every host launches: it lives in the host project's Java
/// package, whatever application ID the host is built with.
const hostActivity = 'com.example.host.MainActivity';

/// One build of the host project.
class Host {
  const Host(this.name, this.id, this.versionName, this.versionCode);
  final String name;
  final String id;
  final String versionName;
  final int versionCode;

  /// Its version as Android's updater reads it from the package.
  String get version => '$versionName+$versionCode';
}

const hostA = Host('A', 'com.example.host_a', '3.1.0', 31);
const hostB = Host('B', 'com.example.host_b', '5.2.0', 52);

/// Host A updated: a new versionName and versionCode, the same app.
const hostA2 = Host('A updated', 'com.example.host_a', '3.2.0', 32);

late Directory work;

Future<void> main(List<String> args) async {
  final hostVersions = args.contains('--host-versions');
  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (positional.length > 1 ||
      args.any((a) => a.startsWith('-') && a != '--host-versions')) {
    print(
      'Usage: dart scripts/module_e2e.dart [--host-versions] '
      '[<flutter-version>]',
    );
    exit(64);
  }
  final flutterVersion = positional.firstOrNull;
  work = Directory.systemTemp.createTempSync('module_e2e_');
  await runE2e(
    title:
        'Add-to-app module on Android '
        '(${flutterVersion ?? 'pinned Flutter'}, '
        '${hostVersions ? 'host versions' : 'module versions'})',
    columns: const ['Check', 'Expected', 'Actual', 'Result'],
    body: () => run(flutterVersion, hostVersions: hostVersions),
    tearDown: () async {
      for (final host in [hostA, hostB]) {
        await Process.run('adb', ['uninstall', host.id]);
      }
      work.deleteSync(recursive: true);
    },
  );
}

Future<void> run(String? flutterVersion, {required bool hostVersions}) async {
  final module = await createModule(work, version: moduleVersion);
  final releaseVersion = hostVersions ? hostA.version : moduleVersion;
  final flutterArgs = [
    if (flutterVersion != null) '--flutter-version=$flutterVersion',
  ];

  await timed(
    'release',
    () => sh(module, 'shorebird', [
      'release',
      'aar',
      '--release-version=$releaseVersion',
      ...flutterArgs,
      '-v',
    ]),
  );
  final baked = RegExp(
    r'^release_version: *(\S+)',
    multiLine: true,
  ).firstMatch(await bundledShorebirdYaml(module))?.group(1);
  check(
    'release_version in the AAR',
    hostVersions ? '(none)' : moduleVersion,
    baked ?? '(none)',
  );

  final project = writeHostProject(module);
  final apks = <Host, File>{};
  for (final host in [hostA, hostB, hostA2]) {
    await timed(
      'build host ${host.name}',
      () async => apks[host] = await buildHost(project, host),
    );
  }

  for (final host in [hostA, hostB]) {
    await Process.run('adb', ['uninstall', host.id]);
    await sh(work, 'adb', ['install', apks[host]!.path]);
    final (:updateLog, :bootLog, :label) = await updateAndBoot(
      'host ${host.name}',
      launcher(host),
    );
    check('host ${host.name} before the patch', 'release', label);
    checkPatchCheck(host, updateLog, releaseVersion, hostVersions);
  }

  setLabel(module, 'patch');
  await timed(
    'patch',
    () => sh(module, 'shorebird', [
      'patch',
      'aar',
      // A patch builds with its release's Flutter; `patch` takes no
      // --flutter-version.
      '--release-version=$releaseVersion',
      '-v',
    ]),
  );

  for (final host in [hostA, hostB]) {
    final (updateLog: _, bootLog: _, :label) = await updateAndBoot(
      'host ${host.name}',
      launcher(host),
    );
    // With host versions only A's version has the release.
    final gets = !hostVersions || host == hostA;
    check(
      'host ${host.name} after the patch',
      gets ? 'patch' : 'release',
      label,
    );
  }

  // `install -r` updates the app in place, keeping its data, as a store
  // update does.
  await sh(work, 'adb', ['install', '-r', apks[hostA2]!.path]);
  // Until its update check finishes, which logs the patch check; the label
  // is printed at boot, before it.
  final (_, firstLog) = await launcher(hostA2)(
    until: RegExp('Update thread finished|Update failed'),
    timeout: updateTimeout,
  );
  check(
    'host A updated to ${hostA2.version}, first launch',
    hostVersions ? 'release' : 'patch',
    labelIn(firstLog) ?? '(no label)',
  );
  if (!hostVersions) checkPatchCheck(hostA2, firstLog, releaseVersion, false);
}

/// Records a row of the report, failing the run if [actual] isn't [want].
void check(String name, String want, String actual) {
  final ok = want == actual;
  if (!ok) failed = true;
  results.add('| $name | $want | $actual | ${ok ? '✅' : '❌'} |');
}

/// Checks the fields [host]'s updater sent in its patch check, from the line
/// it logs (updater network.rs `log_line`). With module versions that's the
/// module's release version and the host's bundle ID and version. With host
/// versions each host sends its own version as the release version, so only
/// that is checked.
void checkPatchCheck(
  Host host,
  String log,
  String releaseVersion,
  bool hostVersions,
) {
  final line = RegExp(
    'Sending patch check request: (.*)',
  ).firstMatch(log)?.group(1);
  // Updaters before network.rs `log_line` printed the request with Debug,
  // which quotes each string.
  String field(String name) => line == null
      ? '(no patch check logged)'
      : RegExp('$name: "?([^,"]+)').firstMatch(line)?.group(1) ?? '(none)';
  final prefix = 'host ${host.name} patch check';
  check(
    '$prefix release_version',
    hostVersions ? host.version : releaseVersion,
    field('release_version'),
  );
  if (hostVersions) return;
  check('$prefix host_bundle_id', host.id, field('host_bundle_id'));
  check('$prefix host_version', host.version, field('host_version'));
}

/// The generated (bundled) shorebird.yaml in the AAR the release built.
Future<String> bundledShorebirdYaml(Directory module) async {
  final aar = File(
    '${module.path}/build/host/outputs/repo/com/example/e2e_module/'
    'flutter_release/1.0/flutter_release-1.0.aar',
  );
  final result = await Process.run('unzip', [
    '-p',
    aar.path,
    'assets/flutter_assets/shorebird.yaml',
  ]);
  if (result.exitCode != 0) throw Exception('unzip: ${result.stderr}');
  return result.stdout as String;
}

/// Writes a native Android app that embeds the module's release AAR from its
/// local Maven repo, as `shorebird release aar` tells customers to, and opens
/// a FlutterActivity. Its application ID and version are Gradle properties,
/// so one project builds every [Host]. It borrows the module template's
/// Gradle wrapper and Android Gradle Plugin version, which the pinned Flutter
/// keeps working together.
Directory writeHostProject(Directory module) {
  final project = Directory('${work.path}/host')..createSync();
  final template = Directory('${module.path}/.android');
  final agp = RegExp(
    r'''id ["']com\.android\.library["'] version ["']([^"']+)["']''',
  ).firstMatch(File('${template.path}/settings.gradle').readAsStringSync());
  if (agp == null) {
    throw Exception(
      "Can't find the Android Gradle Plugin version in the module template's "
      'settings.gradle.',
    );
  }
  for (final name in [
    'gradlew',
    'gradle/wrapper/gradle-wrapper.jar',
    'gradle/wrapper/gradle-wrapper.properties',
  ]) {
    final to = File('${project.path}/$name')
      ..parent.createSync(recursive: true);
    File('${template.path}/$name').copySync(to.path);
  }
  final sdk =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      '${Platform.environment['HOME']}/Library/Android/sdk';
  final downloadUrl =
      (Platform.environment['SHOREBIRD_DOWNLOAD_URL'] ??
              'https://download.shorebird.dev')
          .replaceFirst(RegExp(r'/$'), '');
  final files = {
    'local.properties': 'sdk.dir=$sdk\n',
    'gradle.properties': 'android.useAndroidX=true\n',
    'settings.gradle':
        '''
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id "com.android.application" version "${agp.group(1)}" apply false
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("${module.path}/build/host/outputs/repo") }
        maven { url = uri("$downloadUrl/download.flutter.io") }
    }
}
include ":app"
''',
    'app/build.gradle': '''
plugins {
    id "com.android.application"
}
android {
    namespace = "com.example.host"
    compileSdk = 36
    defaultConfig {
        applicationId = providers.gradleProperty("hostId").get()
        minSdk = 24
        targetSdk = 36
        versionCode = providers.gradleProperty("hostCode").get().toInteger()
        versionName = providers.gradleProperty("hostName").get()
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.debug
        }
    }
}
dependencies {
    releaseImplementation "com.example.e2e_module:flutter_release:1.0"
}
''',
    'app/src/main/AndroidManifest.xml':
        '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="host">
        <activity
            android:name="$hostActivity"
            android:exported="true"
            android:theme="@android:style/Theme.Black.NoTitleBar">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
    'app/src/main/java/com/example/host/MainActivity.java': '''
package com.example.host;

import io.flutter.embedding.android.FlutterActivity;

public class MainActivity extends FlutterActivity {}
''',
  };
  for (final MapEntry(key: path, value: contents) in files.entries) {
    File('${project.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
  }
  return project;
}

/// Builds [host] from [project] and returns its APK, copied out of the
/// build directory the next build overwrites.
Future<File> buildHost(Directory project, Host host) async {
  await sh(project, '${project.path}/gradlew', [
    ':app:assembleRelease',
    '-PhostId=${host.id}',
    '-PhostName=${host.versionName}',
    '-PhostCode=${host.versionCode}',
  ]);
  return File(
    '${project.path}/app/build/outputs/apk/release/app-release.apk',
  ).copySync('${work.path}/host-${host.id}-${host.version}.apk');
}

/// Launches [host] (installed) and reads its log until a line matches
/// `until`. See [Launch].
Launch launcher(Host host) =>
    ({required RegExp until, required Duration timeout}) async {
      final pid = await startAndroidApp(host.id, activity: hostActivity);
      if (pid == null) return (false, 'host ${host.name} exited at launch');
      try {
        final logcat = await Process.start('adb', ['logcat', '--pid=$pid']);
        return await watch(logcat, until: until, timeout: timeout);
      } finally {
        await stopAndroidApp(host.id);
      }
    };
