# Phase 3 API and Implementation Updates

This document records the API and implementation changes made for Phase 3 of `PLAN.md`.

## Public macOS APIs

- [x] Kept `NSURLTagNamesKey` as the file tag read/write API.
- [x] Kept Spotlight-backed `NSMetadataQuery` for `--find` and `--usage`.
- [x] Kept `kMDItemUserTags`, `kMDItemPath`, and metadata query search scopes as the query surface to verify on macOS 15.

No macOS 15 regression was found in the local tag read/write API during the integration test pass.

## Error and Exit Handling

- [x] Added a top-level `runWithArgv:argc:` flow that returns a process status from `main`.
- [x] Changed command-line parsing errors to return exit status `1` instead of calling `exit()`.
- [x] Changed file operation failures to set exit status `2` and stop the current operation instead of calling `exit()`.
- [x] Changed invalid path argument handling to return exit status `3`.
- [x] Included the failing path in file-operation diagnostics where a URL is available.

The existing CLI exit-code meanings are preserved:

- `0`: success, help, or version output.
- `1`: command-line usage or option conflict.
- `2`: file operation or metadata query failure.
- `3`: invalid path argument.

## URL and Output Behavior

- [x] Preserved relative-path output behavior for local file operations.
- [x] Preserved `--nul` line termination behavior.
- [x] Preserved color output gating on `isatty(stdout)`.
- [x] Added directory enumeration error handling so inaccessible descendants are no longer silently ignored.

## Metadata Query Behavior

- [x] Added a bounded wait for `NSMetadataQuery` completion.
- [x] Report a clear error if a metadata query cannot start.
- [x] Report a clear error if a metadata query times out, including a hint that Spotlight may be disabled, unavailable, or still indexing.
- [x] Kept `--find` and `--usage` out of mandatory integration tests because temporary fixtures are not reliably visible to Spotlight immediately.

The Phase 1 probe showed that a freshly-created temporary fixture can produce no `--find` or `--usage` results even when the commands complete successfully. That is a Spotlight indexing constraint rather than deterministic CLI behavior, so local file operations remain the automated test focus.

## String Handling

- [x] Validate tag arguments that cannot be decoded as UTF-8.
- [x] Validate path arguments that cannot be decoded as UTF-8.
- [x] Keep comma escaping unsupported for now, matching the documented compatibility contract.
- [x] Keep case-insensitive tag matching for Finder compatibility.

## Structural Notes

- [x] Separated the process lifecycle into command-line parsing and operation execution return paths.
- [x] Phase 5 later replaced the Objective-C implementation with Swift while preserving these return-code and error-handling behaviors.
