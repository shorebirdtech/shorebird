import 'package:test/test.dart';
import 'package:verify_cache/verify_cache.dart';

void main() {
  const base = CacheKey(
    inputs: {'.': 'abc'},
    directory: '.',
    command: ['tool/agent-verify.sh'],
    tools: {'dart': '3.9', 'node': '24'},
    platform: 'macos_arm64',
  );

  group(CacheKey, () {
    test('equal inputs give equal digests', () {
      const same = CacheKey(
        inputs: {'.': 'abc'},
        directory: '.',
        command: ['tool/agent-verify.sh'],
        // Insertion order is not an input.
        tools: {'node': '24', 'dart': '3.9'},
        platform: 'macos_arm64',
      );
      expect(same.digest, base.digest);
      const twoInputs = CacheKey(
        inputs: {'b': '2', 'a': '1'},
        directory: '.',
        command: ['x'],
        tools: {},
        platform: 'macos_arm64',
      );
      const twoInputsSorted = CacheKey(
        inputs: {'a': '1', 'b': '2'},
        directory: '.',
        command: ['x'],
        tools: {},
        platform: 'macos_arm64',
      );
      expect(twoInputs.digest, twoInputsSorted.digest);
    });

    test('every input changes the digest', () {
      final variants = [
        const CacheKey(
          inputs: {'packages/a': 'abc'},
          directory: '.',
          command: ['tool/agent-verify.sh'],
          tools: {'dart': '3.9', 'node': '24'},
          platform: 'macos_arm64',
        ),
        const CacheKey(
          inputs: {'.': 'abd'},
          directory: '.',
          command: ['tool/agent-verify.sh'],
          tools: {'dart': '3.9', 'node': '24'},
          platform: 'macos_arm64',
        ),
        const CacheKey(
          inputs: {'.': 'abc'},
          directory: 'web',
          command: ['tool/agent-verify.sh'],
          tools: {'dart': '3.9', 'node': '24'},
          platform: 'macos_arm64',
        ),
        const CacheKey(
          inputs: {'.': 'abc'},
          directory: '.',
          command: ['tool/agent-verify.sh', '--plan'],
          tools: {'dart': '3.9', 'node': '24'},
          platform: 'macos_arm64',
        ),
        const CacheKey(
          inputs: {'.': 'abc'},
          directory: '.',
          command: ['tool/agent-verify.sh'],
          tools: {'dart': '3.10', 'node': '24'},
          platform: 'macos_arm64',
        ),
        const CacheKey(
          inputs: {'.': 'abc'},
          directory: '.',
          command: ['tool/agent-verify.sh'],
          tools: {'dart': '3.9'},
          platform: 'macos_arm64',
        ),
        const CacheKey(
          inputs: {'.': 'abc'},
          directory: '.',
          command: ['tool/agent-verify.sh'],
          tools: {'dart': '3.9', 'node': '24'},
          platform: 'linux_x64',
        ),
      ];
      final digests = {base.digest, for (final v in variants) v.digest};
      expect(digests, hasLength(variants.length + 1));
    });

    test('the format version is part of the key', () {
      expect(base.toJson()['format'], CacheKey.formatVersion);
    });
  });

  group('toolVersion', () {
    test('is the first line of --version', () async {
      expect(await toolVersion('git'), startsWith('exit 0: git version '));
    });

    test('is absent for a tool not on the PATH', () async {
      expect(await toolVersion('no-such-tool-verify-cache'), 'absent');
    });
  });

  test('currentPlatform names the OS and architecture', () {
    expect(currentPlatform(), contains('_'));
  });
}
