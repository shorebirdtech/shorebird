# 0.0.4

- feat: add `ttl` (time to live) on `set` API
  ```dart
  redis.set(key: 'hello', value: 'world', ttl: Duration(seconds: 10));
  ```

# 0.0.3

- feat: add [`JSONPath`](https://redis.io/docs/data-types/json/path) support

# 0.0.2

- feat: add new commands:
  - [UNLINK](https://redis.io/commands/unlink)
  - [JSON.MERGE](https://redis.io/commands/json.merge)
- docs: minor improvements to README

# 0.0.1

- feat: initial release 🎉
