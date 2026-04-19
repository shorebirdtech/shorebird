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
  Any shipped binary already contains every define value. Recording them
  server-side is not a net new disclosure.
- Dart-define *keys* usually do NOT survive into the binary — `String.
  fromEnvironment` is evaluated by the front-end compiler, which substitutes
  the value and drops the key. So recording keys is a mild new disclosure, but
  the customer passed the key on the command line at release time knowing it
  would drive the build — the expectation is low.
- Paths (`--split-debug-info`, `--target`, `--export-options-plist`,
  `--dart-define-from-file`, `--public-key-path`, `--private-key-path`) leak
  local workspace layout and occasionally sensitive filenames. **Do not
  record the value.** Record presence only.
- Secrets (private key material, `--sign-cmd`) are obviously off-limits and do
  not affect the snapshot anyway.

We deliberately do not hash values to avoid the complexity — the argument for
hashing is "don't store the plaintext," but per the rule above, plaintext of
binary-embedded values is already public, and plaintext of path/secret values
shouldn't be stored at all.

## Flag taxonomy

Three buckets. Each known shorebird-recognized flag is classified.

### Record value (safe; affects snapshot)

| Flag | Source | Notes |
|---|---|---|
| `--obfuscate` | shorebird | Bool. Already effectively tracked via the obfuscation-map supplement; this makes it explicit. |
| `--tree-shake-icons` / `--no-tree-shake-icons` | flutter (passed via `rest`) | Bool. Changes asset manifest. |
| `--split-per-abi` | shorebird (Android) | Bool. Determines output shape; not strictly a snapshot attribute but changes patch-output expectations. |
| `--dart-define=K=V` | shorebird | Both key and value. Per privacy rule: values are already in the binary. |
| `--dart-define-from-file=<path>` | shorebird | Expand at release time to k=v pairs and record both. The path is a local detail; the file *contents* are binary-embedded and therefore already public. (Open question: file contents can contain entries the user considered file-private — see Open Questions.) |
| `--build-name` | shorebird | String. Bakes into app version. |
| `--build-number` | shorebird | String. Bakes into app version. |
| `--flavor` | shorebird | String. Determines build variant. |
| `--export-method` | shorebird (iOS) | Enum (`app-store` / `ad-hoc` / `development` / `enterprise`). Not a snapshot attribute but affects produced IPA. |

### Record presence only (value is a path or otherwise not-in-binary)

| Flag | Source | Notes |
|---|---|---|
| `--split-debug-info=<path>` | shorebird | Presence means "release was built with split-debug-info" — the patch must also split. We can auto-add `--split-debug-info` at patch time, but with a *new* temp path. |
| `--target=<path>` | shorebird | Entry-point path. Different entry = different snapshot. Presence alone can't tell us the entry — so this bucket means "release used a non-default target; patch must specify one too, and we cannot auto-imply". |
| `--export-options-plist=<path>` | shorebird (iOS) | Presence. |

### Don't record (irrelevant to snapshot identity)

`--codesign`, `--dry-run`, `--confirm`, `--no-confirm`, `--staging`, `--track`,
`--release-version`, `--platforms`, `--public-key-path`, `--private-key-path`,
`--public-key-cmd`, `--sign-cmd`, `--allow-native-diffs`, `--allow-asset-diffs`,
`--min-link-percentage`.

### Unknown flags in `rest`

Everything after `--` that we don't recognize is forwarded to `flutter build`.
We don't know the semantics of arbitrary flutter flags, so conservatively
**record presence only** under a separate `rest_presence` list. That lets us detect drift
without leaking potentially-sensitive values.

## Captured record shape (draft)

One top-level record per release, keyed by release + platform. Draft JSON:

```json
{
  "version": 1,
  "flags": {
    "obfuscate": {"kind": "bool", "value": true},
    "tree-shake-icons": {"kind": "bool", "value": true},
    "split-debug-info": {"kind": "presence"},
    "target": {"kind": "presence"},
    "flavor": {"kind": "value", "value": "production"},
    "build-name": {"kind": "value", "value": "1.2.3"},
    "build-number": {"kind": "value", "value": "45"},
    "export-method": {"kind": "value", "value": "app-store"},
    "dart-define": {
      "kind": "key-value-map",
      "entries": {"SERVER_URL": "https://…", "DISABLE_AUTH": "false"}
    }
  },
  "rest_presence": ["--some-flutter-flag"]
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
  `bool` → read `results[name]`; `value` → read `results[name]` or
  `findOption(..., rest)`; `presence` → `flagPresent(...)` or `optionPresent(...)`
  from the helpers landed in #3698.
- `dart-define-from-file` is expanded inline at release time by reading the
  referenced .json/.env file and merging with `--dart-define` entries (with
  --dart-define winning on key conflict, matching Flutter).
- Unknown `rest` entries are captured as presence-only tokens (stripping
  `=<value>` suffixes before storage).

Upload: TBD, see Storage below.

## Patch-side verification

Implemented as a pure function over `BuildFlagRecord` (from the release) plus
the current `ArgResults`. Three outcome classes:

### 1. Flag with recorded value — auto-imply when missing

If the release had `--obfuscate`, `--flavor=foo`, `--build-name=1.2.3`, etc.,
and the user's current `shorebird patch` invocation doesn't pass the same
value, the patch command synthesizes the flag and passes it through to
flutter. The user sees an info-level log:

```
Applying --flavor=production from release (captured at release time).
```

Exceptions:
- If the user passed the same flag with a **different** value, fail — we do
  not silently override the user's explicit intent.
- If the user passed the same flag with the **same** value, silent no-op.

### 2. Flag with recorded value — `--dart-define` diff

Compare the recorded dart-define map to the patch invocation's map
(`--dart-define` + `--dart-define-from-file`). Diff:

- Release had key `X`, patch missing: auto-add `--dart-define=X=<captured>`,
  info log.
- Release had key `X=a`, patch has `X=b`: fail with message listing the key
  and both values, exit before building.
- Patch has key `Y`, release didn't: fail (new define wasn't in the baseline;
  its constants would appear in patch VM data but not base).

### 3. Flag with recorded presence — must be present, value is user-supplied

`--split-debug-info` and friends. At patch time:

- If the user passed the flag: fine, use their value.
- If they didn't: fail with a specific message naming the flag, e.g.
  `--split-debug-info was used at release time; pass it to this patch too`.

`--target` is the same shape. We can't auto-imply because we didn't record
the path.

### Rest presence

If the release's `rest_presence` contains a token the patch's rest doesn't,
surface a warning (not an error — these are flags we don't understand the
semantics of, so we'd rather be loud than block). Conversely, a new unknown
flag in the patch is also a warning.

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
