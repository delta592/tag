# Swift CLI Test Suite Implementation Guide

This guide lays out a practical, modern test-suite structure for a Swift command-line project targeting macOS 15+.

The recommended design is simple: keep the executable target thin, put real behavior in a library target, test most logic directly, then add subprocess-level tests to verify the actual CLI binary behaves correctly. The Makefile is the source of truth for all developer and CI test commands. Local runs and CI should call the same Make targets so behavior does not drift.

---

## 1. Create the package structure

For a new project:

```bash
mkdir MyTool
cd MyTool
swift package init --type executable
```

Then reshape the package into a testable CLI layout:

```text
Package.swift
Sources/
  MyToolCore/
    MyToolCore.swift
  MyToolCLI/
    main.swift
Tests/
  MyToolCoreTests/
    MyToolCoreTests.swift
  MyToolCLITests/
    CLIRunner.swift
    MyToolCLITests.swift
  Fixtures/
    sample-input.txt
```

The important rule: `MyToolCLI` should mostly parse arguments and call `MyToolCore`. Most actual behavior belongs in `MyToolCore`.

---

## 2. Configure `Package.swift`

Example package configuration:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyTool",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "mytool", targets: ["MyToolCLI"]),
        .library(name: "MyToolCore", targets: ["MyToolCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "MyToolCore"
        ),
        .executableTarget(
            name: "MyToolCLI",
            dependencies: [
                "MyToolCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "MyToolCoreTests",
            dependencies: ["MyToolCore"]
        ),
        .testTarget(
            name: "MyToolCLITests",
            dependencies: []
        )
    ]
)
```

---

## 3. Add a Makefile as the test source of truth

Create a `Makefile` at the package root. This becomes the canonical interface for building, testing, smoke testing, and release artifact validation. Developers should run `make test`, and CI should call the same target instead of invoking `swift test` directly.

```makefile
SHELL := /bin/bash

PRODUCT := mytool
BUILD_DIR := .build
DEBUG_BIN := $(BUILD_DIR)/debug/$(PRODUCT)
RELEASE_BIN := $(BUILD_DIR)/release/$(PRODUCT)
UNIVERSAL_BIN := dist/$(PRODUCT)

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make build              Build debug binary"
	@echo "  make test               Run the full default test suite"
	@echo "  make test-unit          Run Swift tests"
	@echo "  make test-cli           Build debug binary and run CLI smoke tests"
	@echo "  make test-release       Build release binary and run release smoke tests"
	@echo "  make test-universal     Build and validate Universal 2 artifact"
	@echo "  make clean              Remove build artifacts"

.PHONY: build
build:
	swift build

.PHONY: test
test: test-unit test-cli test-release

.PHONY: test-unit
test-unit:
	swift test

.PHONY: test-cli
test-cli: build
	$(DEBUG_BIN) hello | grep -q '^hello$$'
	$(DEBUG_BIN) --help | grep -q 'USAGE:'

.PHONY: test-release
test-release:
	swift build -c release
	$(RELEASE_BIN) hello | grep -q '^hello$$'
	$(RELEASE_BIN) --help | grep -q 'USAGE:'

.PHONY: universal
universal:
	mkdir -p dist
	swift build -c release --arch arm64
	cp $(BUILD_DIR)/arm64-apple-macosx/release/$(PRODUCT) dist/$(PRODUCT)-arm64
	swift build -c release --arch x86_64
	cp $(BUILD_DIR)/x86_64-apple-macosx/release/$(PRODUCT) dist/$(PRODUCT)-x86_64
	lipo -create dist/$(PRODUCT)-arm64 dist/$(PRODUCT)-x86_64 -output $(UNIVERSAL_BIN)

.PHONY: test-universal
test-universal: universal
	lipo -info $(UNIVERSAL_BIN) | grep -q 'arm64'
	lipo -info $(UNIVERSAL_BIN) | grep -q 'x86_64'
	file $(UNIVERSAL_BIN)

.PHONY: clean
clean:
	rm -rf .build dist
```

The exact target names can change, but the principle should not: `make test` is the normal validation path, and CI calls `make test`. Add narrower targets only when they represent useful subsets of the canonical suite.
---

## 4. Put real behavior in the core library

Example core implementation:

```swift
// Sources/MyToolCore/MyToolCore.swift
import Foundation

public struct ToolConfig: Equatable {
    public var uppercase: Bool

    public init(uppercase: Bool = false) {
        self.uppercase = uppercase
    }
}

public enum ToolError: Error, Equatable, LocalizedError {
    case emptyInput

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Input cannot be empty."
        }
    }
}

public struct MyToolCore {
    public init() {}

    public func transform(_ input: String, config: ToolConfig) throws -> String {
        guard !input.isEmpty else {
            throw ToolError.emptyInput
        }

        return config.uppercase ? input.uppercased() : input
    }
}
```

---

## 5. Keep the CLI wrapper thin

Example CLI using Swift Argument Parser:

```swift
// Sources/MyToolCLI/main.swift
import ArgumentParser
import Foundation
import MyToolCore

@main
struct MyTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mytool",
        abstract: "A small example Swift CLI."
    )

    @Flag(help: "Uppercase the input.")
    var uppercase = false

    @Argument(help: "Input text to transform.")
    var input: String

    func run() throws {
        let core = MyToolCore()
        let result = try core.transform(
            input,
            config: ToolConfig(uppercase: uppercase)
        )
        print(result)
    }
}
```

---

## 6. Add fast core logic tests

Use Swift Testing for new tests.

```swift
// Tests/MyToolCoreTests/MyToolCoreTests.swift
import Testing
@testable import MyToolCore

@Suite("MyToolCore behavior")
struct MyToolCoreTests {
    @Test("returns input unchanged by default")
    func defaultTransform() throws {
        let core = MyToolCore()
        let result = try core.transform("hello", config: ToolConfig())
        #expect(result == "hello")
    }

    @Test("uppercases input when configured")
    func uppercaseTransform() throws {
        let core = MyToolCore()
        let result = try core.transform("hello", config: ToolConfig(uppercase: true))
        #expect(result == "HELLO")
    }

    @Test("rejects empty input")
    func rejectsEmptyInput() throws {
        let core = MyToolCore()

        #expect(throws: ToolError.emptyInput) {
            try core.transform("", config: ToolConfig())
        }
    }
}
```

Run through the Makefile:

```bash
make test-unit
```

For the normal full local suite, use:

```bash
make test
```

---

## 7. Add a subprocess test helper for the real CLI

Subprocess tests verify the compiled executable, not just the library.

```swift
// Tests/MyToolCLITests/CLIRunner.swift
import Foundation
import Testing

struct CLIResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum CLIRunner {
    static func run(_ arguments: [String]) throws -> CLIResult {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MyToolCLITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root

        let binaryURL = packageRoot
            .appendingPathComponent(".build/debug/mytool")

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        process.currentDirectoryURL = packageRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
```

Before running CLI subprocess tests, build the executable through the Makefile:

```bash
make build
make test-unit
```

The full suite should still be invoked as:

```bash
make test
```

---

## 8. Add CLI behavior tests

```swift
// Tests/MyToolCLITests/MyToolCLITests.swift
import Testing

@Suite("mytool CLI behavior")
struct MyToolCLITests {
    @Test("prints transformed output")
    func printsOutput() throws {
        let result = try CLIRunner.run(["hello"])

        #expect(result.exitCode == 0)
        #expect(result.stdout == "hello\n")
        #expect(result.stderr == "")
    }

    @Test("supports uppercase flag")
    func supportsUppercaseFlag() throws {
        let result = try CLIRunner.run(["--uppercase", "hello"])

        #expect(result.exitCode == 0)
        #expect(result.stdout == "HELLO\n")
        #expect(result.stderr == "")
    }

    @Test("fails when required argument is missing")
    func missingArgumentFails() throws {
        let result = try CLIRunner.run([])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Missing expected argument"))
    }

    @Test("prints help")
    func printsHelp() throws {
        let result = try CLIRunner.run(["--help"])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("USAGE:"))
        #expect(result.stdout.contains("mytool"))
    }
}
```

---

## 9. Add temporary-directory filesystem tests

For tools that read or write files, always isolate mutations in temporary directories.

```swift
import Foundation
import Testing

func withTemporaryDirectory<T>(
    _ body: (URL) throws -> T
) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )

    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    return try body(directory)
}
```

Example use:

```swift
@Test("writes output file")
func writesOutputFile() throws {
    try withTemporaryDirectory { tempDir in
        let output = tempDir.appendingPathComponent("out.txt")

        // Call core logic or CLI subprocess here.
        try "hello\n".write(to: output, atomically: true, encoding: .utf8)

        let contents = try String(contentsOf: output, encoding: .utf8)
        #expect(contents == "hello\n")
    }
}
```

Filesystem cases worth testing:

- Missing input file
- Existing output file
- No-overwrite behavior
- Explicit overwrite behavior
- Symlink handling
- Directory passed where file expected
- Permission-denied behavior
- Atomic write behavior
- Dry-run behavior
- Timestamp preservation, if applicable

---

## 10. Add fixture-based tests

Use checked-in fixtures for stable sample inputs.

```text
Tests/
  Fixtures/
    basic-input.txt
    malformed-config.json
    expected-output.txt
```

Helper:

```swift
import Foundation

func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
}
```

Best practice: copy fixtures into a temporary directory before mutating them.

---

## 11. Test configuration precedence

For mature CLIs, explicitly test configuration precedence:

```text
CLI flags > environment variables > config file > defaults
```

Recommended cases:

- Default behavior with no config
- Config-file value applies
- Environment value overrides config file
- CLI flag overrides environment
- Invalid config fails cleanly
- Missing config file behavior is intentional

For subprocess tests, inject environment variables through `Process.environment`.

Example adjustment to the runner:

```swift
process.environment = ProcessInfo.processInfo.environment.merging(
    ["MYTOOL_MODE": "strict"],
    uniquingKeysWith: { _, new in new }
)
```

---

## 12. Test exit-code contracts

Define exit-code behavior intentionally. Example:

```text
0   success
1   general runtime failure
2   usage or argument error
64  command-line usage error, if following sysexits-style conventions
66  input file unavailable
73  cannot create output file
```

Then test it through subprocess tests.

At minimum, cover:

- Success
- Usage error
- Missing input
- Invalid input
- Permission error
- Partial failure
- Unexpected internal error

---

## 13. Normalize unstable output

Avoid brittle tests caused by machine-specific values.

Normalize or avoid exact assertions for:

- Absolute paths
- Temporary directory names
- User home paths
- Timestamps
- UUIDs
- Locale-sensitive formatting
- Dictionary ordering
- Filesystem ordering

For stable output, exact assertions are good. For unstable output, assert structure and key substrings.

---

## 14. Add release-build tests

Debug tests are useful, but release builds can expose optimization or packaging issues.

Run locally through the Makefile:

```bash
make test-release
```

This target should build the release binary and run at least `--help` plus one ordinary command.

Expected:

```text
hello
```

---

## 15. Validate Universal 2 artifacts when shipping one binary

For a universal CLI binary, build or combine both slices, then validate the artifact. Put this behind the Makefile rather than keeping it as a separate tribal-knowledge command sequence.

Run:

```bash
make test-universal
```

That target should build both slices, combine them with `lipo`, and fail unless the final artifact contains both `arm64` and `x86_64`.

Expected:

```text
Architectures in the fat file: mytool are: x86_64 arm64
```

Also inspect:

```bash
file mytool
```

If the CLI links native dynamic libraries, those libraries must also exist for the relevant architecture.

---

## 16. Add basic GitHub Actions CI

Example `.github/workflows/test.yml`:

```yaml
name: Test

on:
  push:
  pull_request:

jobs:
  macos:
    runs-on: macos-15

    steps:
      - uses: actions/checkout@v4

      - name: Show Swift version
        run: swift --version

      - name: Run canonical test suite
        run: make test
```

If you ship Universal 2 binaries, add a release-artifact validation job that calls `make test-universal`. CI should not duplicate the `swift build`, `lipo`, or smoke-test logic already defined in the Makefile.

---

## 17. Recommended local developer commands

Fast feedback:

```bash
swift test
```

Build and run manually:

```bash
swift run mytool hello
swift run mytool -- --help
```

Release smoke test:

```bash
swift build -c release
.build/release/mytool hello
```

Check architecture:

```bash
file .build/release/mytool
lipo -info .build/release/mytool
```

---

## 18. Practical test-suite checklist

Use this as the working definition of “comprehensive enough” for a serious Swift CLI:

- Core library tests cover transformation, validation, and error mapping.
- CLI parser tests cover flags, arguments, defaults, subcommands, and help output.
- Subprocess tests assert stdout, stderr, and exit codes.
- Filesystem tests use temporary directories.
- Fixtures are checked in and copied before mutation.
- Config precedence is explicitly tested.
- Dry-run behavior is tested.
- Failure cases are first-class tests, not afterthoughts.
- Release build gets at least a smoke test.
- Universal 2 release artifacts are validated with `lipo -info`.
- CI calls `make test`; the Makefile owns `swift build`, `swift test`, and release smoke checks.

---

## 19. Suggested implementation order

1. Split executable logic into `MyToolCore` and `MyToolCLI`.
2. Add Swift Testing unit tests for `MyToolCore`.
3. Add subprocess runner for the actual CLI binary.
4. Add tests for help, success, invalid arguments, and exit codes.
5. Add temporary-directory helpers.
6. Add fixture tests.
7. Add config precedence tests.
8. Add release-build smoke tests.
9. Add CI that calls `make test`, not raw `swift` commands.
10. Add Universal 2 validation as `make test-universal` only if distributing one binary for both Intel and Apple Silicon Macs.

---

## Bottom line

The most maintainable Swift CLI test suite is layered:

```text
Core library tests     -> fast correctness
Parser tests           -> command contract
Subprocess CLI tests   -> real binary behavior
Filesystem tests       -> real-world safety
Makefile targets       -> one source of truth
Release/arch checks    -> distribution confidence
```

That gives you confidence that the tool works both as Swift code and as the actual binary users will run.
