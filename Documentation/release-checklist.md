# Release Checklist

Use this checklist when preparing a `tag` release.

## Version and Source

- [ ] Update the version string in `Tag/main.swift`.
- [ ] Confirm `README.md` describes the supported macOS version, build commands, install paths, and user-visible behavior.
- [ ] Confirm `Tag/tag.1` matches the README and `tag --help`.
- [ ] Keep `Tag/tag.1` in the repository; it is installed by `make install` as the `man tag` page.

## Build and Test

- [ ] Run the canonical local and CI suite:

  ```sh
  make clean && make test
  ```

- [ ] If debugging a specific layer, use the narrower Make targets:

  ```sh
  make test-lint
  make test-cli
  make test-universal
  make test-install
  make test-xcode
  make test-man
  ```

- [ ] Confirm SwiftLint is installed when preparing a release locally:

  ```sh
  swiftlint version
  make lint-swift
  ```

- [ ] Build a clean Universal 2 binary separately if you need the artifact after tests:

  ```sh
  make clean && make
  make check-universal
  ```

- [ ] Verify staged install paths manually when changing packaging logic:

  ```sh
  dest=$(mktemp -d "${TMPDIR:-/tmp}/tag-install.XXXXXX")
  make install DESTDIR="$dest"
  test -x "$dest/usr/local/bin/tag"
  test -f "$dest/usr/local/share/man/man1/tag.1"
  for arch in arm64 x86_64; do
    lipo "$dest/usr/local/bin/tag" -verify_arch "$arch"
  done
  rm -rf "$dest"
  ```

## Packaging Notes

- [ ] Homebrew formulae should build with `make` and stage with `make install DESTDIR=...` or the equivalent formula prefix staging.
- [ ] MacPorts Portfiles should use the same build and install flow unless the package manager provides a preferred wrapper.
- [ ] Package metadata should state macOS 15 or later.
- [ ] Package checks should verify the installed binary is Universal 2.

## Documentation Source of Truth

The README is the primary long-form user documentation. The man page is maintained manually from the README and `tag --help`; update all three together when command syntax or options change.
