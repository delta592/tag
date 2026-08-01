# Test Suite

The Makefile is the source of truth for local and CI validation. Use `make test` for the full suite.

## Canonical Command

```sh
make clean && make test
```

CI runs the same `make test` target so local and automated validation do not drift.

## Makefile Targets

- `make test`: Runs the full default suite.
- `make test-lint`: Runs SwiftLint when `swiftlint` is installed.
- `make lint-swift`: Runs only SwiftLint, using `.swiftlint.yml`.
- `make test-cli`: Builds `bin/tag` and runs subprocess CLI integration tests.
- `make test-universal`: Verifies the Makefile-built binary contains `arm64` and `x86_64` slices.
- `make test-install`: Stages `make install DESTDIR=...` and verifies the installed binary and man page.
- `make test-xcode`: Builds Xcode Debug and Release outputs and verifies Universal 2 slices.
- `make test-man`: Runs `mandoc -T lint Tag/tag.1` when `mandoc` is available.

CI installs SwiftLint from the repo `Brewfile` before running `make test`, so linting is enforced in GitHub Actions. Local runs skip SwiftLint with a message if it is not installed. Install it with:

```sh
brew bundle
```

## CLI Integration Coverage

`Tests/integration.sh` exercises the real compiled binary in temporary directories. It covers:

- Help and version output.
- `--set`, `--add`, `--remove`, `--list`, and `--match`.
- Tags with spaces and empty tag sets.
- Case-insensitive matching.
- Short-option clusters such as `-tgm`.
- Recursive traversal, `--enter`, hidden files, and `--all`.
- `--slash` directory output.
- `--nul` output for script use.
- Default `--list` behavior when no operation or path is provided.
- Duplicate operation errors and missing-path failures.
- Finder color fallback behavior for missing, unreadable, and changed preference data.
- `--find` and `--usage` smoke checks to ensure Spotlight-backed operations complete without hanging.

The tests intentionally avoid exact result assertions for Spotlight-backed `--find` and `--usage` because fresh temporary files may not be indexed immediately.

## Test Isolation

The CLI tests create temporary files and directories under `mktemp` and clean them up automatically. Finder color preference tests use `TAG_FINDER_PREFERENCES_PATH` to avoid reading or modifying the developer's real Finder preferences.

## Non-Goals

This project does not currently use Swift Package Manager or a separate Swift library target. The current suite therefore focuses on subprocess tests of the actual binary plus distribution checks. If the implementation is later split into a reusable Swift library, add fast Swift unit tests for parser, formatter, tag-store, and color-provider logic while keeping the subprocess tests for end-to-end coverage.
