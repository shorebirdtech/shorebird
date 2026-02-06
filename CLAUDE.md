# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Bootstrap: Install dependencies for all packages
./scripts/bootstrap.sh

# Run all tests (must run from packages/ directory to avoid cache conflicts)
cd packages && very_good test -r

# Run tests for a single package
dart test packages/shorebird_cli

# Run a single test file
dart test packages/shorebird_cli/test/src/commands/patch/patch_command_test.dart

# Run tests with reduced output (only show failures)
dart test -r failures-only packages/shorebird_cli

# Format code
dart format .

# Analyze code
dart analyze --fatal-warnings lib test

# Generate code (for packages using json_serializable/build_runner)
dart run build_runner build --delete-conflicting-outputs
```

## Project Structure

This is a Dart monorepo using workspaces (see root `pubspec.yaml`). The main package is `shorebird_cli` - a CLI tool for Shorebird's code push service that enables over-the-air updates for Flutter apps.

### Key Packages

- **shorebird_cli**: Main CLI tool (the `shorebird` command)
- **shorebird_code_push_client**: API client for Shorebird backend
- **shorebird_code_push_protocol**: Shared protocol/models between client and server
- **scoped_deps**: Zone-based dependency injection library used throughout

### CLI Architecture (shorebird_cli)

Commands inherit from `ShorebirdCommand` ([shorebird_command.dart](packages/shorebird_cli/lib/src/shorebird_command.dart)) and are registered in `ShorebirdCliCommandRunner` ([shorebird_cli_command_runner.dart](packages/shorebird_cli/lib/src/shorebird_cli_command_runner.dart)).

**Platform-specific operations** use the Releaser/Patcher pattern:
- `release/` contains `Releaser` base class with platform implementations (AndroidReleaser, IosReleaser, etc.)
- `patch/` contains `Patcher` base class with platform implementations (AndroidPatcher, IosPatcher, etc.)

**Dependency Injection** uses `scoped_deps`:
```dart
// Define a reference
final authRef = create(Auth.new);

// Access in current scope
Auth get auth => read(authRef);

// Override in tests
runScoped(() => myTest(), values: {authRef.overrideWith(() => mockAuth)});
```

Services like `auth`, `shorebirdEnv`, `shorebirdProcess` are accessed via refs defined in their respective files.

## Code Style

- Uses `very_good_analysis` lint rules
- 100% test coverage required
- Tests use `mocktail` for mocking
- Page width: 80 characters
- PR titles must follow semantic commit format (enforced in CI)
- CSpell: use inline `// cspell:words` directives for words in 1-2 files; add to the global cspell config for words appearing in more files
- When working on PRs, prefer making new commits rather than amending existing ones - it's simpler and the history gets squashed anyway
