# verify_cache

Runs a verification command at most once per set of inputs. `tool/agent-verify.sh`
goes through it, so a tree that already passed in any worktree is answered
from the cache instead of being checked again.

```bash
dart run verify_cache [--force] [--tool <name>]... [--input <path>]... \
  [--dart-package <path>] [--cache-dir <dir>] -- <command> [<arg>...]
```

A pass is recorded under `~/.cache/shorebird-verify-cache/passed/<key>`. The
key is a SHA-256 over:

- the git hash of each input as the working tree holds it: the whole working
  tree by default, which covers the command's own script and every lockfile
- the directory and the command, as written
- the first line of `--version` for each `--tool`
- the platform (`Abi.current()`)

The working tree is hashed as it is on disk, through a copy of the index and
`git write-tree`: committed, staged, modified and untracked files alike, and
ignored files not, since those are build outputs and installs that the
lockfiles describe. A run over an uncommitted change is cached like any
other, and putting a file back as it was finds its earlier pass.

`--input` narrows the key to the paths given, relative to the checkout root,
so a change elsewhere keeps the pass. `--dart-package <path>` adds that
package's inputs: the package, every package it reaches through `path:`
dependencies or a dependency on another workspace member (which pub resolves
to that member whatever version it names), its own `dev_dependencies`
included, and the workspace `pubspec.yaml`, `pubspec.lock` and
`analysis_options.yaml`.
`tool/agent-verify.sh` checks each workspace package this way.

`--lookup` runs nothing and answers for many packages at once. Each
`--dart-package` names one, `{}` in the command stands for it, and it prints
a JSON list of those already passed, with the same keys a run records:

```bash
dart run verify_cache --lookup --dart-package packages/a --dart-package packages/b \
  --tool dart -- dart check.dart {}
# ["packages/b"]
```

`tool/agent-verify.sh` asks this once and runs only the rest. Starting a
`dart run` per package costs a second or more each before it finds a pass, so
42 packages that all passed took 451 s at a load average of 44 on 10-21, and
one lookup took 3.4 s.

Nothing finds a test that reads a file outside its package. Such a package
lists those files in its pubspec, relative to the package:

```yaml
verify_cache:
  inputs:
    - ../../web/packages/shorebird-api/src/role_permissions.json
```

A read left unlisted passes from the cache after that file changes, until CI,
which caches nothing, fails it.

What it refuses to trust:

- Only exit code 0 is recorded. Failures always rerun.
- A pass is recorded only if the inputs hash the same when the command exits,
  so neither the command nor an edit made while it ran can record a pass over
  files it did not check.

Concurrent runs over one key take an OS file lock (`RandomAccessFile.lock`),
so the second waits for the first and then takes its pass. The kernel drops
the lock when its holder exits, so a killed run leaves nothing to clean up.

At most two runs check something at once on one machine, and the rest wait
in a queue, saying so. Overlapping runs share the same cores and finish no
sooner than they would one after another: on 10-21, four agent-verify runs
at once took 880 to 1,290 s each against about 300 s alone, drove a 12-core
machine's load average to 92, and timed tests out. A recorded pass never
waits, since only a run that is about to check takes a slot. A slot is an OS
file lock under `slots/`, so a killed run frees its slot too.
`VERIFY_CACHE_SLOTS` sets the number (`0` for no limit). A command run under
a slot gets `VERIFY_CACHE_SLOT_HELD=1`, so a verify_cache inside it, as
agent-verify runs for each Dart package, uses its parent's slot rather than
waiting for a second one.

This is a stopgap facade. A build system with hermetic, content-addressed
action caching (Bazel or similar) would replace it, and callers would keep
calling `tool/agent-verify.sh`.
