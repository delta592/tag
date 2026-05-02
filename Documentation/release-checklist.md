# Release Checklist

Use this checklist when preparing a `tag` release.

## Version and Source

- [ ] Update the version string in `Tag/main.swift`.
- [ ] Confirm `README.md` describes the supported macOS version, build commands, install paths, and user-visible behavior.
- [ ] Confirm `Tag/tag.1` matches the README and `tag --help`.
- [ ] Keep `Tag/tag.1` in the repository; it is installed by `make install` as the `man tag` page.

## Build and Test

- [ ] Build a clean Universal 2 binary:

  ```sh
  make clean && make
  ```

- [ ] Verify Universal 2 slices:

  ```sh
  make check-universal
  ```

- [ ] Run integration tests:

  ```sh
  Tests/integration.sh
  ```

- [ ] Verify Xcode Debug and Release outputs:

  ```sh
  xcodebuild -project Tag.xcodeproj -target Tag -configuration Debug build
  lipo build/Debug/tag -verify_arch arm64 x86_64
  xcodebuild -project Tag.xcodeproj -target Tag -configuration Release build
  lipo build/Release/tag -verify_arch arm64 x86_64
  ```

- [ ] Verify staged install paths:

  ```sh
  dest=$(mktemp -d "${TMPDIR:-/tmp}/tag-install.XXXXXX")
  make install DESTDIR="$dest"
  test -x "$dest/usr/local/bin/tag"
  test -f "$dest/usr/local/share/man/man1/tag.1"
  lipo "$dest/usr/local/bin/tag" -verify_arch arm64 x86_64
  rm -rf "$dest"
  ```

## Packaging Notes

- [ ] Homebrew formulae should build with `make` and stage with `make install DESTDIR=...` or the equivalent formula prefix staging.
- [ ] MacPorts Portfiles should use the same build and install flow unless the package manager provides a preferred wrapper.
- [ ] Package metadata should state macOS 15 or later.
- [ ] Package checks should verify the installed binary is Universal 2.

## Documentation Source of Truth

The README is the primary long-form user documentation. The man page is maintained manually from the README and `tag --help`; update all three together when command syntax or options change.
