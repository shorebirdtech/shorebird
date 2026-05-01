# Build Flag Capture Notes

Working design notes for recording the build flags used at `shorebird release` time
so `shorebird patch` can verify (or automatically re-apply) the same flags, and
surface precise errors when it can't.

Status: **design, not yet implemented**. Storage shape is deliberately left open
for cloud review.

## Motivation

`shorebird patch` fails with `link_failure: base and patch snapshots have
differing VM sections` whenever the patch build's AOT snapshot diverges from the
release baseline in a way the linker can't reconcile. In practice, the common
cause is that the release and patch were built with a different *flag set*:

- Different `--dart-define` values produce different compile-time constants in
  the VM data section (matching instruction hash, differing data hash — the
  exact signature in #3695).
- A release built with `--obfuscate` must also be patched with `--obfuscate`,
  otherwise the identifier-renamed strings in VM data diverge.
- `--split-debug-info`, `--tree-shake-icons`, `--flavor`, `--build-name`,
  `--build-number`, and `--target` all similarly affect the produced snapshot.

Today the linker reports a raw hash mismatch and the user is left reverse-
engineering which flag drifted. The CLI-side hint landed in #3699 helps, but
only narrows the search — it cannot tell the user *which* flag. We want to:

1. Tell the user exactly which flag changed.
2. Auto-apply the release's flags at patch time where we safely can, so users
   who run `shorebird patch` with no flags get a correct build.
3. Fail early (before invoking the linker) with an actionable message when we
   can't auto-apply.

## Goals

- Record, at `shorebird release` time, the set of flags that affect the produced
  AOT snapshot.
- At `shorebird patch` time, verify the current invocation's flags match the
  recorded set and auto-apply any whose values we stored.
- When a recorded flag differs or is missing, fail with a specific diff listing
  the exact flag(s) involved, before we build or link.
- Preserve back-compat: an old release (no captured flags) should patch exactly
  as it does today, with no new errors.

## Non-goals

- Capturing flags that don't affect the compiled snapshot (`--dry-run`,
  `--codesign`, `--confirm`, `--platforms`, signing-key locations, etc.).
- Full dependency capture (pubspec.lock diffs, engine revision, etc.) — those
  are already handled elsewhere or out of scope for this work.
- Normalizing snapshot hashes to *ignore* flag differences — we want to detect
  and surface them, not paper over them.
- End-to-end integration tests — deferred until storage is decided in review.

## Privacy principles

**Rule of thumb:** if a flag's value is already materialized into the binary
the customer ships, it is safe to record. If it is not, default to recording
only presence.

- Values of `--dart-define=KEY=VALUE` are constant-folded into the AOT snapshot
  (`String.fromEnvironment('KEY')` returns the value as a compile-time const).
  Any shipped binary contains every define value. Recording them server-side
  is not a net new disclosure.
- Dart-define *keys* are stripped when used in a `const` context (the front
  end fully evaluates the call and the key literal has no other reference),
  but DO survive into the binary when used in a non-const context (e.g.
  `var x = String.fromEnvironment('KEY');`). Idiomatic Dart uses const
  (`static const X = String.fromEnvironment('KEY');`), so in practice keys
  are usually stripped — but not guaranteed. We treat keys as "already in the
  binary in the common case," which under our rule makes them recordable, but
  it's worth being explicit that this is a mild additional disclosure in the
  minority non-const case. Verified empirically by compiling a small test
  program and grepping the AOT output.
- Paths (`--split-debug-info`, `--target`, `--export-options-plist`,
  `--dart-define-from-file`, `--public-key-path`, `--private-key-path`) leak
  local workspace layout and occasionally sensitive filenames. **Do not
  record the value.** Record presence only.
- Secrets (private key material, `--sign-cmd`) are obviously off-limits and do
  not affect the snapshot anyway.

We deliberately do not hash values:

- For values already in the binary (dart-define values), hashing buys no
  privacy and only adds complexity.
- For paths and other not-in-binary values, hashing would also be useless for
  verification — the same release rebuilt on a different machine (different
  `$HOME`, workspace layout, CI runner) produces different path hashes
  without anything meaningful having changed. The comparison would be pure
  noise. What's actually useful for paths is *presence* ("was
  --split-debug-info used at all?"), not value equality.

So: record plaintext where it's safe and meaningful, record presence where
it isn't, don't hash.

## Flag taxonomy

The scope here is the AOT snapshot specifically — i.e. what ends up in the
`__snapshot_data` / `__snapshot_instructions` sections that the linker
compares. A flag belongs in this document only if it changes those bytes.

The AOT snapshot is produced by `gen_snapshot`, whose inputs are:

1. The kernel (.dill) compiled from the Dart source, which bakes in every
   `String.fromEnvironment` / `int.fromEnvironment` / `bool.fromEnvironment`
   value evaluated at compile time, and is rooted at the user's entry point.
2. `gen_snapshot` flags like `--obfuscate`, `--save-obfuscation-map`, and
   `--strip`.

So the flags that materially affect snapshot bytes are a small set:

- `--obfuscate` — drives identifier renaming in VM data and changes
  `gen_snapshot`'s argv via `addObfuscationMapArgs`.
- `--dart-define=K=V` and `--dart-define-from-file=<path>` — values are
  constant-folded into the kernel → into VM data.
- `--target=<path>` — selects the entry point, which roots tree-shaking and
  determines what's in the kernel.
- `--split-debug-info=<path>` — required companion to `--obfuscate` (Flutter
  rejects obfuscation without it). Controls whether `gen_snapshot` strips
  DWARF. It primarily changes DWARF sections rather than the VM snapshot
  sections, but its presence correlates with obfuscation's strip-behavior, so
  we track it for completeness and to auto-apply alongside `--obfuscate`.

Everything else is out of scope for this doc. Notable exclusions:

- **`--build-name`, `--build-number`** — land in `AndroidManifest.xml` /
  `Info.plist`, not in the AOT snapshot. Patch-time consistency is already
  handled by `Patcher.buildNameAndNumberArgsFromReleaseVersion`
  (`patcher.dart:279`), which auto-injects them from the stored
  `releaseVersion`.
- **`--flavor`** — selects an Android product flavor / iOS scheme. Only
  affects the snapshot transitively, via whatever `--target` and
  `--dart-define`s the flavor implies — both of which we already capture.
- **`--tree-shake-icons`** — changes the bundled icon font bytes (asset), not
  the AOT snapshot. Asset diffs are checked separately by `PatchDiffChecker`.
- **`--split-per-abi`** — chooses which architectures are emitted; each arch
  already has its own independent snapshot.
- **`--export-method`, `--export-options-plist`** — iOS IPA packaging,
  post-snapshot.
- **`--codesign`, `--dry-run`, `--confirm`, `--no-confirm`, `--staging`,
  `--track`, `--release-version`, `--platforms`, signing keys
  (`--public-key-path`, `--private-key-path`, `--public-key-cmd`,
  `--sign-cmd`), `--allow-native-diffs`, `--allow-asset-diffs`,
  `--min-link-percentage`** — CLI behavior, lookup keys, signing, or gating,
  not snapshot inputs.

### Classification

| Flag | Bucket | Rationale |
|---|---|---|
| `--obfuscate` | Record value (bool) | Drives gen_snapshot identifier renaming; values in VM data. |
| `--dart-define=K=V` | Record value (map of k→v) | Per privacy rule, values are already const-folded into the shipped binary. |
| `--dart-define-from-file=<path>` | Record value (expand file to k→v, merge with `--dart-define`) | Same as above after expansion; path itself not recorded. |
| `--target=<path>` | Record presence | Different entry = different snapshot; path is local, can't auto-imply. |
| `--split-debug-info=<path>` | Record presence | Required companion to `--obfuscate`; auto-apply at patch time with a new temp path when release had it. |

### Unknown flags in `rest`

Everything after `--` that shorebird doesn't recognize is forwarded to
`flutter build`. For v1 we **do not** attempt to capture unknown rest flags
— we don't know whether they affect the snapshot, and the conservative
privacy stance (don't record paths or unknown-shape values) means presence-
only tracking is the most we could do, which is weak signal. If a specific
flutter flag turns out to matter in practice we'll classify it explicitly
and move it into the known set.

## Captured record shape (draft)

One top-level record per release, keyed by release + platform. Draft JSON:

```json
{
  "version": 1,
  "flags": {
    "obfuscate": {"kind": "bool", "value": true},
    "split-debug-info": {"kind": "presence"},
    "target": {"kind": "presence"},
    "dart-define": {
      "kind": "key-value-map",
      "entries": {"SERVER_URL": "https://…", "DISABLE_AUTH": "false"}
    }
  }
}
```

`version` lets us evolve the shape; patch-side reader falls back to "unknown
schema, skip verification" on version mismatch rather than erroring.

## Release-side capture

Implemented as a pure function over `ArgResults` + a known-flags table:

```dart
BuildFlagRecord captureBuildFlags(ArgResults results);
```

- Classifier table maps flag name → (bucket, extractor). Extractors are small:
  `bool` → `flagPresent(name)`; `presence` → `optionPresent(name)`; dart-defines
  → read multi-option values plus `findOption(..., rest)` for post-`--` entries.
  All helpers live on the `ArgResults` extension (landed in #3698).
- `dart-define-from-file` is expanded inline at release time by reading the
  referenced .json/.env file and merging with `--dart-define` entries, with
  `--dart-define` winning on key conflict (matching Flutter's behavior).

Upload: TBD, see Storage below.

## Patch-side verification

Implemented as a pure function over `BuildFlagRecord` (from the release) plus
the current `ArgResults`. Three outcome classes:

### 1. `--obfuscate` — auto-imply when missing

If the release recorded `obfuscate: true`:

- Patch passed `--obfuscate` too: silent no-op.
- Patch didn't pass `--obfuscate`: auto-apply it, log at info level
  (`Applying --obfuscate from release`). Also auto-add a `--split-debug-info`
  pointing at a fresh temp directory, since Flutter requires the two together
  and we recorded only the *presence* of `--split-debug-info`, not its path.
- Patch passed `--no-obfuscate` (or shorebird registered `--obfuscate` as
  `negatable: false` today, in which case this is unreachable): fail. Do not
  silently override user intent.

If the release recorded `obfuscate: false` but the patch invocation passed
`--obfuscate`: fail (the existing check at `patch_command.dart:440` already
does this via the obfuscation-map supplement; post-implementation we can fold
both checks into the flag-capture path).

### 2. `--dart-define` diff

Compare the recorded dart-define map to the patch invocation's combined map
(`--dart-define` + `--dart-define-from-file`). Diff, in precedence order:

- Release had key `X=a`, patch has `X=b`: **fail** with message listing the
  key and both values, exit before building.
- Patch has key `Y`, release didn't: **fail** (the new define would produce
  VM-data constants present in patch but not in base).
- Release had key `X`, patch missing: **auto-add** `--dart-define=X=<captured>`,
  info log.

### 3. `--target` — require presence, don't auto-imply

If the release recorded `target: presence`:

- Patch passed `--target=<something>`: accept the user's path; we can't
  validate it matches because we didn't record the value.
- Patch didn't pass `--target`: fail with a specific message —
  `the release was built with a non-default --target; pass --target to this
  patch as well.`

### 4. `--split-debug-info` — follow from `--obfuscate` behavior

If the release recorded `split-debug-info: presence` (which in practice means
the release was obfuscated; the flag is a required companion), the
auto-apply path under case (1) handles it. No separate verification needed.

## Storage (deferred)

`shorebird` has not historically stored structured per-release data that the
runtime depends on. We have three plausible homes and need cloud-team input
before committing:

- **A. Supplement artifact** — reuse the existing `build/<platform>/shorebird/`
  directory and the `uploadSupplementArtifact` machinery that the obfuscation
  map already rides. Add a `build_flags.json` alongside `obfuscation_map.json`.
  - Pros: zero server work; pattern precedent; keyed naturally by release +
    platform.
  - Cons: supplement upload is a separate network call (see the TODO at
    `releaser.dart:184`) so a mid-upload interruption leaves partial state.
    This affects obfuscation today and would affect flag capture the same way.
- **B. Release-metadata field** — extend `UpdateReleaseMetadata` with a
  `buildFlags` field.
  - Pros: one network call, inline with release.
  - Cons: metadata has historically been informational; making patch-time
    correctness depend on it is a change in its role. Also potentially large
    (dart-defines).
- **C. Dedicated endpoint + DB table** — a first-class API for the flag
  manifest.
  - Pros: clean separation, queryable, not tied to artifact-upload flow.
  - Cons: most server work. Probably the right long-term answer.

**Recommendation**: (A) for this PR, since it matches the existing pattern and
avoids server changes; revisit (C) if the supplement-upload atomicity issue
referenced in `releaser.dart:184` becomes a blocker. **To be decided with the
cloud owner during review.**

## Backward / forward compatibility

- **Old release, new patch CLI**: no captured record; patch-side verifier
  treats missing record as "unknown, proceed" — current behavior preserved.
- **New release, old patch CLI**: old CLI ignores the new supplement entry /
  metadata field. User loses the verification but the release is still
  patchable.
- **Schema evolution**: `version` field; unknown future versions skip
  verification rather than error.

## Open questions

1. **`--dart-define-from-file` expansion vs. keys-only.** The privacy rule
   says values are already in the binary, so expanding and recording all k/v
   pairs is consistent. But users sometimes put defines in a file *precisely*
   because the file is a locally-gitignored secret store. Conservative
   alternative: record only the key set, treat as "presence-only" diffing.
   Flagged for review.
2. **`--target` auto-imply.** We could instead record the target *value* —
   it's a path but usually points at a source file in the repo, which is
   part of the customer's source tree. Rule-following says don't record;
   pragmatism says this one is low risk. Leaning "don't record" for v1.
3. **Per-release hash of the whole captured record.** Could expose a single
   hash the user can paste into bug reports; cheap to compute, no privacy
   cost. Not blocking.
4. **Storage atomicity.** See Storage (A) above — do we want to fix the
   mid-upload-interruption bug before layering more state onto the supplement?

## Out-of-scope follow-ups

- Record pubspec.lock hash (or flutter/engine revision diff) for similar
  pre-flight validation against a different class of drift.
- Extend the classifier to cover flags we add in the future — new flags
  default to "don't record" until explicitly classified.
- Surface the captured flags in `shorebird releases list` so customers can
  self-diagnose.
