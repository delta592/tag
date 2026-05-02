# Phase 2A Universal 2 Binaries

This document records the Universal 2 build changes made for Phase 2A of `PLAN.md`.

## Decision

- [x] The default `make` build is the documented distribution build.
- [x] The default `make` build now produces one Universal 2 executable containing `arm64` and `x86_64` slices.
- [x] Single-architecture local builds remain available through `make native` or by overriding `ARCHS`.

The package-manager path uses `make install`, so making `make` Universal 2 by default keeps local builds, CI, and packaged installs aligned.

## Makefile Commands

Build the default Universal 2 binary:

```sh
make clean && make
```

Verify the binary contains both slices:

```sh
make check-universal
```

Build only for the current machine architecture:

```sh
make native
```

Build a specific architecture explicitly:

```sh
make clean && make ARCHS=arm64
make clean && make ARCHS=x86_64
```

Install the Universal 2 binary into a staging root:

```sh
make clean && make
make install DESTDIR=/tmp/tag-package-root
```

## Xcode Verification

The Xcode target is expected to produce one Universal 2 binary for Debug and Release when built with the repository project settings.

```sh
xcodebuild -project Tag.xcodeproj -target Tag -configuration Debug build
lipo build/Debug/tag -verify_arch arm64 x86_64

xcodebuild -project Tag.xcodeproj -target Tag -configuration Release build
lipo build/Release/tag -verify_arch arm64 x86_64
```

## CI

- [x] CI verifies the Makefile binary with `make check-universal`.
- [x] CI verifies the Xcode Debug binary with `lipo`.
- [x] CI verifies the Xcode Release binary with `lipo`.
