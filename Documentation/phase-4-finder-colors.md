# Phase 4 Finder Tag Colors

This document records the Finder tag color preservation work made for Phase 4 of `PLAN.md`.

## Decision

- [x] `--color` remains a core feature.
- [x] Standard Finder color names continue to map to terminal colors when color output is enabled.
- [x] Exact Finder tag-name-to-color lookup remains best-effort because Apple exposes tag names through public APIs, but not a stable public API for Finder's tag color preference mapping.
- [x] A user-configurable color map is deferred. It may be useful later as a fallback or override, but it should not replace Finder color integration.

## API Boundary

File tags are still read and written through the public `NSURLTagNamesKey` resource key.

Finder color lookup is different: Finder stores the user's tag color mapping in Finder preference data. The project now isolates that private preference integration behind small internal helpers so future changes are contained. If Finder changes the preference file path or structure, tag operations and non-color output still work.

The implementation now uses this order:

1. Load built-in standard Finder color-name defaults for `Red`, `Orange`, `Yellow`, `Green`, `Blue`, `Purple`, and `Gray`.
2. Try to read Finder's synced preferences and merge any available tag color mappings.
3. Ignore missing, unreadable, invalid, or structurally changed Finder preference data.
4. Emit ANSI color only when `--color` is requested and stdout is a terminal.

## Testing

- [x] Integration tests cover missing Finder color preferences.
- [x] Integration tests cover structurally changed Finder color preferences.
- [x] Integration tests verify `--color` does not emit ANSI escapes when stdout is not a terminal.

The tests use `TAG_FINDER_PREFERENCES_PATH` to point the color provider at temporary fixtures. This keeps tests isolated from the developer's real Finder preferences.

## Commands

Run the integration tests:

```sh
make
Tests/integration.sh
```

Manually inspect color output in a terminal:

```sh
tag --list --color <path>
```
