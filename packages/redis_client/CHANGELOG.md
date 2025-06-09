# 0.0.9

- fix: expose RedisTDigest type

# 0.0.8

- feat: add limited support for tdigest data structure

# 0.0.7

- feat: add new commands:
  - [TS.CREATE](https://redis.io/commands/ts.create)
  - [TS.ADD](https://redis.io/commands/ts.add)
  - [TS.GET](https://redis.io/commands/ts.get)
  - [TS.RANGE](https://redis.io/commands/ts.range)

# 0.0.6

- feat: add new commands:
  - [MSET](https://redis.io/commands/mset)

# 0.0.5

- feat: add new commands:
  - [MGET](https://redis.io/commands/mget)
  - [INCR](https://redis.io/commands/incr)
  - [INCRBYFLOAT](https://redis.io/commands/incrbyfloat)

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
