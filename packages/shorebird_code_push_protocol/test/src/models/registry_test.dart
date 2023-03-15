import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Registry', () {
    test('can be (de)serialized', () {
      final registry = Registry(
        accounts: [
          Account(
            apiKey: 'api_key1',
            apps: [
              App(
                id: 'app1',
                releases: [
                  Release(
                    version: '1.0.0',
                    patches: [
                      const Patch(
                        number: 1,
                        artifacts: [
                          Artifact(
                            arch: 'aarm64',
                            platform: 'android',
                            url: 'localhost',
                            hash: '#',
                          )
                        ],
                        channels: ['stable'],
                      ),
                      const Patch(
                        number: 2,
                        artifacts: [
                          Artifact(
                            arch: 'aarm64',
                            platform: 'android',
                            url: 'localhost',
                            hash: '#',
                          )
                        ],
                        channels: ['stable'],
                      )
                    ],
                  ),
                  Release(version: '1.0.1'),
                ],
              ),
              App(id: 'app2'),
            ],
          ),
          Account(
            apiKey: 'api_key2',
            apps: [
              App(
                id: 'app2',
                releases: [
                  Release(
                    version: '1.0.0',
                    patches: [
                      const Patch(
                        number: 1,
                        artifacts: [
                          Artifact(
                            arch: 'aarm64',
                            platform: 'android',
                            url: 'localhost',
                            hash: '#',
                          )
                        ],
                        channels: ['stable'],
                      ),
                      const Patch(
                        number: 2,
                        artifacts: [
                          Artifact(
                            arch: 'aarm64',
                            platform: 'android',
                            url: 'localhost',
                            hash: '#',
                          )
                        ],
                        channels: ['stable'],
                      )
                    ],
                  ),
                  Release(version: '2.0.0'),
                ],
              ),
            ],
          ),
        ],
      );

      expect(
        Registry.fromJson(registry.toJson()).toJson(),
        equals(registry.toJson()),
      );
    });
  });
}
