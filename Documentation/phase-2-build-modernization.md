# Phase 2 Build Modernization

This document records the build infrastructure changes made for Phase 2 of `PLAN.md`.

## Xcode Project

- [x] Set the project and target deployment target to macOS 15.0.
- [x] Updated project metadata from the old Xcode 3.2 compatibility era.
- [x] Removed the prefix header from the Xcode build because each Objective-C source imports what it needs directly.
- [x] Kept ARC enabled for Xcode builds.
- [x] Verified Debug and Release builds with `xcodebuild`.

Commands:

```sh
xcodebuild -project Tag.xcodeproj -target Tag -configuration Debug build
xcodebuild -project Tag.xcodeproj -target Tag -configuration Release build
```

## Makefile

- [x] Kept the existing `make`, `make install`, `DESTDIR`, `prefix`, and uninstall workflow for package managers.
- [x] Switched the default compiler invocation to `xcrun clang`.
- [x] Enabled ARC explicitly outside Xcode.
- [x] Passed `-mmacosx-version-min=15.0` explicitly.
- [x] Resolved the macOS SDK through `xcrun --sdk macosx --show-sdk-path`.
- [x] Phase 2A updated the default Makefile build to produce a Universal 2 binary. See `Documentation/phase-2a-universal-2.md`.

Commands:

```sh
make clean && make
make install DESTDIR=/tmp/tag-package-root
```

## CI

- [x] Added `.github/workflows/ci.yml`.
- [x] CI builds with the Makefile.
- [x] CI runs the CLI integration tests.
- [x] CI builds the Xcode target in Debug and Release.
- [x] CI runs on `macos-latest` so the project follows the newest generally available GitHub-hosted macOS image.

## Swift Package Manager Decision

- [x] Deferred adding a Swift Package Manager manifest.

The project is still Objective-C, has no third-party dependencies, and already has package-manager-friendly Makefile install targets. Adding SwiftPM now would introduce a second project model without reducing build complexity. Revisit this if the codebase moves to Swift or if package distribution needs change.
