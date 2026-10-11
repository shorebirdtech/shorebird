import 'dart:io';

import 'package:args/args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/linux_bundle_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

// Behavior shared with WindowsPatcher is tested in desktop_patcher_test.dart;
// this file covers only what is specific to Linux.
void main() {
  group(LinuxPatcher, () {
    late ArgParser argParser;
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
    late Directory bundleDirectory;
    late Doctor doctor;
    late Linux linux;
    late LinuxPatcher patcher;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          artifactManagerRef.overrideWith(() => artifactManager),
          doctorRef.overrideWith(() => doctor),
          linuxRef.overrideWith(() => linux),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
    });

    setUp(() {
      argParser = MockArgParser();
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      bundleDirectory = Directory.systemTemp.createTempSync();
      doctor = MockDoctor();
      linux = MockLinux();

      when(
        () => artifactManager.linuxBundleDirectory,
      ).thenReturn(bundleDirectory);

      patcher = LinuxPatcher(
        argParser: argParser,
        argResults: argResults,
        flavor: null,
        target: 'lib/main_dev.dart',
      );
    });

    test('requires minimumSupportedLinuxFlutterVersion', () {
      expect(
        patcher.minimumFlutterVersion,
        minimumSupportedLinuxFlutterVersion,
      );
    });

    test('identifies as the linux release type', () {
      expect(patcher.releaseType, ReleaseType.linux);
      expect(
        patcher.primaryReleaseArtifactArch,
        primaryLinuxReleaseArtifactArch,
      );
      expect(patcher.supplementaryReleaseArtifactArch, 'linux_supplement');
    });

    test('validates with the linux validators on linux', () {
      final validators = <Validator>[MockValidator()];
      when(() => doctor.linuxCommandValidators).thenReturn(validators);

      expect(runWithOverrides(() => patcher.commandValidators), validators);
      expect(patcher.hostOperatingSystem, NativePlatform.linux);
    });

    test('diffs archives with LinuxBundleDiffer', () {
      expect(patcher.archiveDiffer, const LinuxBundleDiffer());
    });

    test('patches lib/libapp.so in the bundle directory', () {
      expect(runWithOverrides(() => patcher.appDirectory), bundleDirectory);
      expect(patcher.dartLibraryPathSegments, ['lib', 'libapp.so']);
    });

    group('buildApp', () {
      test('builds the linux app and returns the bundle directory', () async {
        when(
          () => artifactBuilder.buildLinuxApp(
            target: any(named: 'target'),
            args: any(named: 'args'),
            base64PublicKey: any(named: 'base64PublicKey'),
          ),
        ).thenAnswer((_) async {});

        final directory = await runWithOverrides(
          () => patcher.buildApp(args: ['--foo'], base64PublicKey: 'key'),
        );

        expect(directory, bundleDirectory);
        verify(
          () => artifactBuilder.buildLinuxApp(
            target: 'lib/main_dev.dart',
            args: ['--foo'],
            base64PublicKey: 'key',
          ),
        ).called(1);
      });
    });

    group('versionFromAppDirectory', () {
      test('reads the version from the bundle', () async {
        final directory = Directory('bundle');
        when(
          () => linux.versionFromLinuxBundle(
            bundleRoot: any(named: 'bundleRoot'),
          ),
        ).thenReturn('1.2.3');

        final version = await runWithOverrides(
          () => patcher.versionFromAppDirectory(directory),
        );

        expect(version, '1.2.3');
        verify(
          () => linux.versionFromLinuxBundle(bundleRoot: directory),
        ).called(1);
      });
    });
  });
}
