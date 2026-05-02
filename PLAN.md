# Modernization Plan

This project is a small macOS command-line tool for reading, writing, matching, and searching Finder tags. The current codebase is Objective-C, Foundation/CoreServices based, and still carries build assumptions from the macOS 10.9 era. The modernization target is macOS 15 and later.

## Goals

- Keep the existing `tag` command behavior stable unless a change is explicitly called out below.
- Move the build and packaging story to current macOS and Xcode expectations.
- Replace brittle or private implementation details where macOS 15 offers a supported path.
- Add enough automated coverage to make future refactors safe.
- Preserve terminal-friendly behavior, including `--nul`, recursive enumeration, and scriptable output.

## Initial State

- At plan creation, the Xcode project used an old compatibility level (`Xcode 3.2`) and a macOS 10.9 deployment target.
- At plan creation, the Makefile built with a direct compiler invocation and did not clearly mirror Xcode's ARC or deployment target settings.
- The app uses public `NSURLTagNamesKey` APIs for reading and writing tags, which should remain the baseline implementation.
- `--find` and `--usage` use `NSMetadataQuery` and Spotlight metadata attributes.
- `--color` reads Finder's synced preferences directly, which is private, fragile, and called out in the README as best-effort behavior.
- At plan creation, there was no visible automated test suite, CI workflow, formatting rule, or release checklist.

## Phase 1: Establish a Safe Baseline

- [x] Build the current project with the latest available Xcode command-line tools.
- [x] Record current behavior with a small manual fixture:
  - [x] Files with no tags.
  - [x] Files with one tag.
  - [x] Files with multiple tags.
  - [x] Directories with tags.
  - [x] Hidden files and recursive directory traversal.
- [x] Capture command behavior for the major modes:
  - [x] `--list`
  - [x] `--set`
  - [x] `--add`
  - [x] `--remove`
  - [x] `--match`
  - [x] `--find`
  - [x] `--usage`
- [x] Decide which legacy behaviors are contractual:
  - [x] Case-insensitive tag matching.
  - [x] Comma-separated tag parsing without comma escaping.
  - [x] `-d`/`--descend` as an alias for `--recursive`.
  - [x] Defaulting to `--list` when no operation is provided.
- [x] Add a lightweight test harness before broad rewrites. Prefer integration tests that run the built `tag` binary against temporary files because the public surface is the CLI.

## Phase 2: Modernize Build Infrastructure

- [x] Update the Xcode project:
  - [x] Set `MACOSX_DEPLOYMENT_TARGET = 15.0`.
  - [x] Run Xcode's project modernization so `LastUpgradeCheck`, project compatibility, warnings, and recommended settings are current.
  - [x] Remove the prefix header unless a current build setting still requires it.
  - [x] Make build settings explicit at the target level where it improves reproducibility.
- [x] Update the Makefile or replace it with a clearer primary build path:
  - [x] Ensure ARC is enabled consistently when building outside Xcode.
  - [x] Pass the macOS 15 deployment target explicitly.
  - [x] Use `xcrun clang` or `xcodebuild` consistently instead of relying on whichever `cc` appears first.
  - [x] Keep `DESTDIR`, `prefix`, man page installation, and uninstall support for package managers.
- [x] Consider adding a Swift Package Manager manifest only if it improves CLI development and packaging without disrupting Homebrew/MacPorts workflows.
- [x] Add CI:
  - [x] Build in Debug and Release.
  - [x] Run CLI integration tests.
  - [x] Run on the newest available macOS runner.

## Phase 2A: Produce Universal 2 Binaries

- [x] Decide whether Universal 2 should be required for every local `make` build or only for release/distribution builds.
- [x] Update the Makefile so the documented distribution build produces one Universal 2 binary with both `arm64` and `x86_64` slices.
- [x] Keep a simple way to build a single-architecture binary for local development if needed.
- [x] Verify the Xcode build also produces a Universal 2 binary, not separate Intel and Apple Silicon outputs.
- [x] Add a CI check that inspects the built executable with `lipo -info` or `file` and fails unless both `arm64` and `x86_64` are present.
- [x] Document the Universal 2 build command and verification command in the README.
- [x] Ensure `make install DESTDIR=...` installs the Universal 2 binary for packaging workflows.

## Phase 3: API and Implementation Updates

- [x] Keep `NSURLTagNamesKey` for file tag reads and writes unless testing shows a macOS 15 regression.
- [x] Audit all file URL handling:
  - [x] Prefer standardized file URLs where user-visible output remains unchanged.
  - [x] Preserve relative path output for existing commands.
  - [x] Handle symlinks, inaccessible paths, and deleted files consistently.
- [x] Revisit `NSMetadataQuery` usage:
  - [x] Verify `kMDItemUserTags`, `kMDItemPath`, and search scopes still behave as expected on macOS 15.
  - [x] Add timeouts or clearer error reporting if Spotlight metadata is unavailable, disabled, or still indexing.
  - [x] Document why `--find` and `--usage` are not deterministic enough for temporary-fixture CI tests.
- [x] Replace process-wide `exit()` calls in implementation methods with error returns at the core logic layer. Keep the CLI exit codes compatible at `main`.
- [x] Split command-line parsing, tag operations, output formatting, and metadata search into smaller units after tests exist.
- [x] Review string handling:
  - [x] Validate invalid UTF-8 paths or arguments.
  - [x] Decide whether comma escaping should remain unsupported or become a new feature.
  - [x] Use localized/case-insensitive comparison only where it matches Finder behavior.
- [x] Review output:
  - [x] Preserve `--nul` exactly for scripting.
  - [x] Avoid ANSI color unless stdout is a terminal.
  - [x] Keep stderr diagnostics actionable and include the path when an operation fails.

## Phase 4: Replace Fragile Tag Color Support

- [ ] Treat the current Finder preference parsing as technical debt because it depends on private data shape.
- [ ] Investigate whether macOS 15 exposes a supported API for Finder tag color metadata.
- [ ] If no supported API exists, choose one of these paths:
  - [ ] Keep `--color` as explicitly best-effort and add tests that tolerate missing colors.
  - [ ] Replace it with a user-configurable color map.
  - [ ] Deprecate `--color` and document why exact Finder colors are not supported.
- [ ] Do not let color lookup failures affect tag operations or non-color output.

## Phase 5: Modernize Language and Structure

- [ ] Prefer an incremental Objective-C cleanup first:
  - [ ] Add nullability annotations to headers.
  - [ ] Use lightweight generics for collections.
  - [ ] Make immutable properties explicit.
  - [ ] Remove unused comments and stale future notes after moving useful ideas into issues.
- [ ] Evaluate a Swift rewrite only after the test harness is in place:
  - [ ] Swift could simplify argument parsing, value types, and tests.
  - [ ] Objective-C may remain the lower-risk choice for a small mature CLI with simple Foundation usage.
- [ ] If moving to Swift, keep the binary name, CLI syntax, exit codes, man page, and package-manager install paths stable.

## Phase 6: Documentation and Distribution

- [ ] Update README references from "Mac OS X 10.9 Mavericks and above" to "macOS 15 and later".
- [ ] Regenerate the man page from a single source of truth or document the manual update process.
- [ ] Fix documentation drift:
  - [ ] The README uses `--nul`; the man page currently documents `--null`.
  - [ ] The man page contains a typo in the `--network` option line.
- [ ] Add a release checklist:
  - [ ] Version bump.
  - [ ] README update.
  - [ ] Man page update.
  - [ ] Build and test commands.
  - [ ] Homebrew/MacPorts packaging notes.

## Suggested Milestones

- [ ] Baseline branch: build current code, add CLI integration tests, and document current behavior.
- [ ] Build modernization branch: update deployment target, project settings, Makefile, and CI.
- [ ] Universal 2 distribution branch: produce and verify a single binary containing both Apple Silicon and Intel slices.
- [ ] Internal cleanup branch: separate parsing, operations, output, and metadata search with no intended behavior change.
- [ ] macOS 15 behavior branch: address Spotlight query behavior, error handling, and tag color policy.
- [ ] Documentation branch: update README, man page, install instructions, and release checklist.

## Acceptance Criteria

- [ ] `tag` builds from a clean checkout on macOS 15+ using the documented command.
- [ ] The documented distribution build produces a Universal 2 `tag` binary with `arm64` and `x86_64` slices.
- [ ] Automated tests cover the main CLI modes and pass in CI.
- [ ] `make install DESTDIR=...` or the chosen replacement works for packaging.
- [ ] Existing documented command syntax continues to work unless a breaking change is explicitly approved.
- [ ] Private Finder preference parsing is either removed, isolated behind a documented best-effort boundary, or replaced with a supported/configurable approach.
- [ ] README and man page agree on supported macOS versions, options, and installation paths.
