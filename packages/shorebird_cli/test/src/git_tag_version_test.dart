import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/git_tag_version.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockProcessResult extends Mock implements ProcessResult {}

void main() {
  const shorebirdChannel = 'main';
  const shorebirdStableRevision = 'revision-1';
  const shorebirdStableVersion = 'v1.0.0';
  const shorebirdDevRevision = 'revision-2';
  const shorebirdDevVersion = 'v1.0.0-1.1.pre';
  const shorebirdNoTagRevision = 'revision-3';
  const shorebirdNoTagVersion = 'v1.2.3-4.5.pre-6-gabc123';

  group('GitTagVersion', () {
    late ShorebirdProcess shorebirdProcess;
    late ProcessResult fetchChannelResult;
    late ProcessResult fetchStableTagResult;
    late ProcessResult fetchDevTagResult;
    late ProcessResult fetchNoTagResult;
    late ProcessResult fetchNearestTagResult;
    late ProcessResult fetchRemoteTagsResult;

    setUp(() {
      shorebirdProcess = _MockShorebirdProcess();
      fetchChannelResult = _MockProcessResult();
      fetchStableTagResult = _MockProcessResult();
      fetchDevTagResult = _MockProcessResult();
      fetchNoTagResult = _MockProcessResult();
      fetchNearestTagResult = _MockProcessResult();
      fetchRemoteTagsResult = _MockProcessResult();
      when(
        () => shorebirdProcess.runSync(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenReturn(fetchChannelResult);
      when(
        () => shorebirdProcess.runSync(
          'git',
          ['fetch', shorebirdGit, '--tags', '-f'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenReturn(fetchRemoteTagsResult);
      when(
        () => shorebirdProcess.runSync(
          'git',
          ['tag', '--points-at', shorebirdStableRevision],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenReturn(fetchStableTagResult);
      when(
        () => shorebirdProcess.runSync(
          'git',
          ['tag', '--points-at', shorebirdDevRevision],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenReturn(fetchDevTagResult);
      when(
        () => shorebirdProcess.runSync(
          'git',
          ['tag', '--points-at', shorebirdNoTagRevision],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenReturn(fetchNoTagResult);

      when(
        () => shorebirdProcess.runSync(
          'git',
          ['tag', '--points-at', shorebirdNoTagRevision],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenReturn(fetchNearestTagResult);
    });

    group('determine', () {
      test('stable', () {
        when(
          () => fetchChannelResult.stdout,
        ).thenReturn(shorebirdChannel);
        when(
          () => fetchStableTagResult.stdout,
        ).thenReturn(shorebirdStableVersion);
        final gitTagVersion = GitTagVersion.determine(
          shorebirdProcess,
          fetchTags: true,
          workingDirectory: '.',
          gitRef: shorebirdStableRevision,
        );
        expect(
          gitTagVersion.frameworkVersionFor(shorebirdStableVersion),
          '1.0.0',
        );
      });

      test('dev', () {
        when(
          () => fetchChannelResult.stdout,
        ).thenReturn(shorebirdChannel);
        when(
          () => fetchDevTagResult.stdout,
        ).thenReturn(shorebirdDevVersion);
        final gitTagVersion = GitTagVersion.determine(
          shorebirdProcess,
          fetchTags: true,
          workingDirectory: '.',
          gitRef: shorebirdDevRevision,
        );
        expect(
          gitTagVersion.frameworkVersionFor(shorebirdDevRevision),
          '1.0.0-1.1.pre',
        );
      });

      test('noTag', () {
        when(
          () => fetchChannelResult.stdout,
        ).thenReturn(shorebirdChannel);
        when(
          () => fetchNoTagResult.stdout,
        ).thenReturn(shorebirdNoTagVersion);
        when(
          () => fetchNearestTagResult.stdout,
        ).thenReturn(shorebirdDevVersion);

        final gitTagVersion = GitTagVersion.determine(
          shorebirdProcess,
          fetchTags: true,
          workingDirectory: '.',
          gitRef: shorebirdNoTagRevision,
        );
        expect(
          gitTagVersion.frameworkVersionFor(shorebirdNoTagRevision),
          '1.0.0-1.1.pre',
        );
      });
    });

    test('parseVersion', () {
      const hash = 'abcdef';
      GitTagVersion gitTagVersion;

      // main channel
      gitTagVersion = GitTagVersion.parseVersion('v1.2.0-4.5.pre-13-g$hash');
      expect(gitTagVersion.frameworkVersionFor(hash), '1.2.1-0.0.pre.13');
      expect(gitTagVersion.gitTag, '1.2.0-4.5.pre');
      expect(gitTagVersion.devVersion, 4);
      expect(gitTagVersion.devPatch, 5);

      // Stable channel
      gitTagVersion = GitTagVersion.parseVersion('v1.2.3');
      expect(gitTagVersion.frameworkVersionFor(hash), '1.2.3');
      expect(gitTagVersion.x, 1);
      expect(gitTagVersion.y, 2);
      expect(gitTagVersion.z, 3);
      expect(gitTagVersion.devVersion, null);
      expect(gitTagVersion.devPatch, null);

      // Dev channel
      gitTagVersion = GitTagVersion.parseVersion('v1.2.3-4.5.pre');
      expect(gitTagVersion.frameworkVersionFor(hash), '1.2.3-4.5.pre');
      expect(gitTagVersion.gitTag, '1.2.3-4.5.pre');
      expect(gitTagVersion.devVersion, 4);
      expect(gitTagVersion.devPatch, 5);

      gitTagVersion = GitTagVersion.parseVersion('v1.2.3-13-g$hash');
      expect(gitTagVersion.frameworkVersionFor(hash), '1.2.4-0.0.pre.13');
      expect(gitTagVersion.gitTag, '1.2.3');
      expect(gitTagVersion.devVersion, null);
      expect(gitTagVersion.devPatch, null);

      // new tag release format, dev channel
      gitTagVersion = GitTagVersion.parseVersion('v1.2.3-4.5.pre-0-g$hash');
      expect(gitTagVersion.frameworkVersionFor(hash), '1.2.3-4.5.pre');
      expect(gitTagVersion.gitTag, '1.2.3-4.5.pre');
      expect(gitTagVersion.devVersion, 4);
      expect(gitTagVersion.devPatch, 5);

      // new tag release format, stable channel
      gitTagVersion = GitTagVersion.parseVersion('v1.2.3-13-g$hash');
      expect(gitTagVersion.frameworkVersionFor(hash), '1.2.4-0.0.pre.13');
      expect(gitTagVersion.gitTag, '1.2.3');
      expect(gitTagVersion.devVersion, null);
      expect(gitTagVersion.devPatch, null);

      expect(
        GitTagVersion.parseVersion('v98.76.54-32-g$hash')
            .frameworkVersionFor(hash),
        '98.76.55-0.0.pre.32',
      );
      expect(
        GitTagVersion.parseVersion('v10.20.30-0-g$hash')
            .frameworkVersionFor(hash),
        '10.20.30',
      );
      expect(
        GitTagVersion.parseVersion('v1.2.3+hotfix.1-4-g$hash')
            .frameworkVersionFor(hash),
        '0.0.0-unknown',
      );
      expect(
        GitTagVersion.parseVersion('vx1.2.3-4-g$hash')
            .frameworkVersionFor(hash),
        '0.0.0-unknown',
      );
      expect(
        GitTagVersion.parseVersion('v1.0.0-unknown-0-g$hash')
            .frameworkVersionFor(hash),
        '0.0.0-unknown',
      );
      expect(
        GitTagVersion.parseVersion('vbeta-1-g$hash').frameworkVersionFor(hash),
        '0.0.0-unknown',
      );
      expect(
        GitTagVersion.parseVersion('v1.2.3-4-gx$hash')
            .frameworkVersionFor(hash),
        '0.0.0-unknown',
      );
    });
  });
}
