# Phase 1 Baseline

This document captures the modernization baseline before changing behavior or updating the project to macOS 15+. It is intended to support Phase 1 of `PLAN.md`.

## Build Baseline

- [x] `make clean && make` succeeds with the current command-line tools.
- [x] The Makefile produces `bin/tag`.
- [x] `xcodebuild -project Tag.xcodeproj -target Tag -configuration Debug build` was attempted with the current Xcode.
- [x] The Xcode build currently fails because the project still targets macOS 10.9 and the current SDK no longer provides ARC support for that deployment target.

The Xcode failure is expected modernization input for Phase 2, not a Phase 1 fix. The relevant failure is:

```text
clang: error: SDK does not contain 'libarclite' ... try increasing the minimum deployment target
warning: The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.9
```

## Test Fixture Coverage

The integration test harness in `Tests/integration.sh` creates a temporary fixture with:

- [x] A file with no tags.
- [x] A file with one tag.
- [x] A file with multiple tags.
- [x] A tagged directory.
- [x] A tagged child file.
- [x] A tagged hidden file for `--all` and recursive traversal checks.

The fixture is created under `mktemp`, uses the built `tag` binary, and is removed automatically at the end of the test run.

## Captured Command Behavior

The Phase 1 integration harness captures these behaviors:

- [x] `--list --no-name` returns only tag names for tagged files.
- [x] `--list --no-name` returns no output for an untagged file.
- [x] `--set` replaces the full tag list.
- [x] `--add` preserves existing tags and adds new tags.
- [x] `--remove` removes a specific tag.
- [x] `--remove '*'` clears all tags.
- [x] `--match` compares tags case-insensitively.
- [x] `--match --no-name --tags` emits tags only for matching files.
- [x] `--list --recursive` includes the provided directory and visible descendants.
- [x] `--list --recursive` skips hidden files by default.
- [x] `--list --recursive --all` includes hidden files.

Spotlight-backed behavior was also probed manually:

- [x] `--find Alpha <temporary-directory>` completed successfully but returned no results for a freshly-created temporary fixture.
- [x] `--usage Alpha <temporary-directory>` completed successfully but returned no results for a freshly-created temporary fixture.

That result suggests these modes depend on Spotlight indexing state and should receive dedicated Phase 3 treatment before they are required in CI.

## Contractual Legacy Behavior

These behaviors should be treated as compatibility contracts unless a breaking change is explicitly approved:

- [x] Tag matching remains case-insensitive.
- [x] Tags are parsed as comma-separated values.
- [x] Commas inside tag names remain unsupported until a new escaping design is approved.
- [x] `-d` and `--descend` remain aliases for `--recursive`.
- [x] The default operation remains `--list` when no operation is provided.
- [x] `--all`, `--enter`, and `--recursive` continue to affect file enumeration for local file operations.
- [x] `--nul` remains the scriptable line terminator option.

## Commands

Build:

```sh
make clean && make
```

Run integration tests:

```sh
Tests/integration.sh
```

Run tests against a different binary:

```sh
TAG_BIN=/path/to/tag Tests/integration.sh
```
