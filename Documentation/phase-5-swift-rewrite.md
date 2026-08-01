# Phase 5 Swift Rewrite

This document records the Swift rewrite completed for Phase 5 of `PLAN.md`.

## Decision

- [x] Swift is now the implementation language for the `tag` CLI.
- [x] The rewrite preserves the existing binary name, command syntax, exit-code meanings, man page, and install paths.
- [x] The Objective-C implementation was kept as the behavior reference until the Swift implementation passed the integration suite.
- [x] The Objective-C source files were removed after Makefile, Xcode, Universal 2, and integration-test parity passed.

The project now targets macOS 15+, has a behavior baseline, and has CI-oriented integration tests. That makes Swift the better long-term fit for current macOS development practices.

## Structure

The Swift implementation lives in `Tag/main.swift` and keeps the command internals split into focused types:

- [x] `TagCLI` for command parsing and operation dispatch.
- [x] `TagName` for Finder-compatible case-insensitive tag identity.
- [x] `FinderTagColorProvider` for standard Finder colors and best-effort Finder preference integration.
- [x] `MetadataQueryObserver` for bounded Spotlight query completion.
- [x] Small URL/output helpers for tag writes and terminal-safe output.

The rewrite intentionally did not introduce `swift-argument-parser` yet. A custom parser keeps legacy syntax details under direct control, including default `--list`, `-d`/`--descend`, option clusters such as `-tgm`, and optional `--usage` tags.

## Build Impact

- [x] `make` now compiles Swift sources with `xcrun swiftc`.
- [x] The Makefile still produces a Universal 2 binary by compiling each architecture and combining with `lipo`.
- [x] The Xcode target now builds `main.swift`.
- [x] The old Objective-C source files are no longer part of the project.

## Compatibility Guardrails

- [x] Existing integration tests pass against the Swift binary.
- [x] Universal 2 checks pass for Makefile and Xcode outputs.
- [x] `make install DESTDIR=...` still stages the binary and man page in the same locations.
- [x] Finder color behavior remains best-effort and protected by fallback tests.
