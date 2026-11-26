import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/patch/patch_link.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group('resolvePatchLink', () {
    const sha = 'abc1234def5678abc1234def5678abc1234def56';
    final projectRoot = Directory('project');

    late Git git;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          gitRef.overrideWith(() => git),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    void stubCheckout({required String status}) {
      when(
        () => git.revParse(revision: 'HEAD', directory: projectRoot.path),
      ).thenAnswer((_) async => sha);
      when(
        () => git.statusPorcelain(directory: projectRoot.path),
      ).thenAnswer((_) async => status);
    }

    void stubNoCheckout() {
      when(
        () => git.revParse(
          revision: any(named: 'revision'),
          directory: any(named: 'directory'),
        ),
      ).thenThrow(const ProcessException('git', ['rev-parse']));
    }

    Future<PatchLinkPlan> resolve({
      String? patchKey,
      bool noLink = false,
      List<ReleasePlatform> platforms = const [ReleasePlatform.android],
    }) => runWithOverrides(
      () => resolvePatchLink(
        patchKey: patchKey,
        noLink: noLink,
        platforms: platforms,
        projectRoot: projectRoot,
      ),
    );

    setUp(() {
      git = MockGit();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);
    });

    group('with --patch-key', () {
      test('uses the key and records the commit', () async {
        stubCheckout(status: ' M lib/main.dart\n');

        final link = await resolve(patchKey: 'my-key');

        expect(link.key, equals('my-key'));
        expect(link.source, equals(PatchLinkSource.flag));
        expect(link.checkout?.sha, equals(sha));
        expect(link.checkout?.dirty, isTrue);
        expect(link.canSkipPublished, isFalse);
      });

      test('does not skip published platforms on a clean tree', () async {
        stubCheckout(status: '');

        final link = await resolve(patchKey: 'my-key');

        expect(link.checkout?.dirty, isFalse);
        expect(link.canSkipPublished, isFalse);
      });

      test('uses the key outside a git checkout', () async {
        stubNoCheckout();

        final link = await resolve(patchKey: 'my-key');

        expect(link.key, equals('my-key'));
        expect(link.checkout, isNull);
      });
    });

    test('with --no-link has no key but records the commit', () async {
      stubCheckout(status: '');

      final link = await resolve(
        noLink: true,
        platforms: [ReleasePlatform.android, ReleasePlatform.ios],
      );

      expect(link.key, isNull);
      expect(link.source, isNull);
      expect(link.checkout?.sha, equals(sha));
      expect(link.checkout?.dirty, isFalse);
      verifyNever(() => logger.info(any()));
    });

    test("on a clean tree uses HEAD's SHA", () async {
      stubCheckout(status: '\n');

      final link = await resolve();

      expect(link.key, equals(sha));
      expect(link.source, equals(PatchLinkSource.commit));
      expect(link.checkout?.dirty, isFalse);
      expect(link.canSkipPublished, isTrue);
      verifyNever(() => logger.info(any()));
    });

    group('on a dirty tree', () {
      setUp(() => stubCheckout(status: '?? notes.txt\n'));

      test("on CI uses HEAD's SHA and says the tree is dirty", () async {
        when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);

        final link = await resolve();

        expect(link.key, equals(sha));
        expect(link.source, equals(PatchLinkSource.commit));
        expect(link.checkout?.dirty, isTrue);
        expect(link.canSkipPublished, isFalse);
        verify(
          () => logger.info(
            any(
              that: allOf(
                contains('uncommitted changes'),
                contains('linked by commit abc1234'),
              ),
            ),
          ),
        ).called(1);
      });

      test('off CI does not link and says how to', () async {
        final link = await resolve(
          platforms: [ReleasePlatform.android, ReleasePlatform.ios],
        );

        expect(link.key, isNull);
        expect(link.checkout?.dirty, isTrue);
        verify(
          () => logger.info(
            any(
              that: allOf(
                startsWith('Not linked: the working tree has uncommitted'),
                contains('--patch-key=<key>'),
              ),
            ),
          ),
        ).called(1);
      });
    });

    group('outside a git checkout', () {
      setUp(stubNoCheckout);

      test('with several platforms uses one random key', () async {
        final link = await resolve(
          platforms: [ReleasePlatform.android, ReleasePlatform.ios],
        );

        expect(link.key, matches(RegExp(r'^[0-9a-f-]{36}$')));
        expect(link.source, equals(PatchLinkSource.random));
        expect(link.checkout, isNull);
        expect(link.canSkipPublished, isFalse);
      });

      test('with one platform does not link', () async {
        final link = await resolve();

        expect(link.key, isNull);
        expect(link.checkout, isNull);
        verify(
          () => logger.detail(any(that: startsWith('Not linked'))),
        ).called(1);
      });
    });
  });

  group('GitCheckout', () {
    test('shortSha is the first seven characters', () {
      expect(
        const GitCheckout(sha: 'abcdef0123', dirty: false).shortSha,
        equals('abcdef0'),
      );
      expect(
        const GitCheckout(sha: 'abc', dirty: false).shortSha,
        equals('abc'),
      );
    });
  });
}
