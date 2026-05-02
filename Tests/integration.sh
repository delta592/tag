#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TAG_BIN=${TAG_BIN:-"$ROOT_DIR/bin/tag"}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    expected=$1
    actual=$2
    label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: <%s>\nactual:   <%s>\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_contains() {
    needle=$1
    haystack=$2
    label=$3

    case "$haystack" in
        *"$needle"*) ;;
        *) fail "$label: expected output to contain <$needle>; actual output was <$haystack>" ;;
    esac
}

assert_not_contains() {
    needle=$1
    haystack=$2
    label=$3

    case "$haystack" in
        *"$needle"*) fail "$label: expected output not to contain <$needle>; actual output was <$haystack>" ;;
        *) ;;
    esac
}

LAST_OUTPUT=
assert_status() {
    expected=$1
    label=$2
    shift 2

    set +e
    LAST_OUTPUT=$("$@" 2>&1)
    actual=$?
    set -e

    if [ "$actual" -ne "$expected" ]; then
        printf 'FAIL: %s\nexpected status: <%s>\nactual status:   <%s>\noutput: <%s>\n' "$label" "$expected" "$actual" "$LAST_OUTPUT" >&2
        exit 1
    fi
}

if [ ! -x "$TAG_BIN" ]; then
    fail "tag binary not found at $TAG_BIN; run 'make' first or set TAG_BIN"
fi

assert_status 0 "help exits successfully" "$TAG_BIN" --help
assert_contains "usage:" "$LAST_OUTPUT" "help includes usage text"
assert_contains "--add" "$LAST_OUTPUT" "help includes long options"

assert_status 0 "version exits successfully" "$TAG_BIN" --version
assert_contains "v0.10.0" "$LAST_OUTPUT" "version includes current version"

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tag-tests.XXXXXX")
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ONE_TAG_FILE="$TMP_DIR/one.txt"
MULTI_TAG_FILE="$TMP_DIR/multi.txt"
UNTAGGED_FILE="$TMP_DIR/untagged.txt"
SPACE_TAG_FILE="$TMP_DIR/space tag.txt"
FIXTURE_DIR="$TMP_DIR/fixture-dir"
CHILD_FILE="$FIXTURE_DIR/child.txt"
HIDDEN_FILE="$FIXTURE_DIR/.hidden.txt"

mkdir -p "$FIXTURE_DIR"
printf 'one\n' > "$ONE_TAG_FILE"
printf 'multi\n' > "$MULTI_TAG_FILE"
printf 'none\n' > "$UNTAGGED_FILE"
printf 'space\n' > "$SPACE_TAG_FILE"
printf 'child\n' > "$CHILD_FILE"
printf 'hidden\n' > "$HIDDEN_FILE"

"$TAG_BIN" --set Alpha "$ONE_TAG_FILE"
assert_eq "Alpha" "$("$TAG_BIN" --list --no-name "$ONE_TAG_FILE")" "set/list single tag"

"$TAG_BIN" --set Alpha,Beta "$MULTI_TAG_FILE"
assert_eq "Alpha,Beta" "$("$TAG_BIN" --list --no-name "$MULTI_TAG_FILE")" "set/list multiple tags"

assert_eq "" "$("$TAG_BIN" --list --no-name "$UNTAGGED_FILE")" "list untagged file with no-name"

"$TAG_BIN" --set "multi word" "$SPACE_TAG_FILE"
assert_eq "multi word" "$("$TAG_BIN" --list --no-name "$SPACE_TAG_FILE")" "tags may contain spaces"

"$TAG_BIN" --set "" "$SPACE_TAG_FILE"
assert_eq "" "$("$TAG_BIN" --list --no-name "$SPACE_TAG_FILE")" "empty set clears tags"

"$TAG_BIN" --add Gamma "$ONE_TAG_FILE"
assert_eq "Alpha,Gamma" "$("$TAG_BIN" --list --no-name "$ONE_TAG_FILE")" "add preserves existing tags"

"$TAG_BIN" --remove Alpha "$ONE_TAG_FILE"
assert_eq "Gamma" "$("$TAG_BIN" --list --no-name "$ONE_TAG_FILE")" "remove one tag"

"$TAG_BIN" --remove '*' "$ONE_TAG_FILE"
assert_eq "" "$("$TAG_BIN" --list --no-name "$ONE_TAG_FILE")" "remove wildcard clears tags"

match_output=$("$TAG_BIN" --match beta --no-name --tags "$ONE_TAG_FILE" "$MULTI_TAG_FILE")
assert_eq "Alpha,Beta" "$match_output" "match is case-insensitive and requires matching files only"

cluster_output=$("$TAG_BIN" -tgm beta "$MULTI_TAG_FILE")
assert_contains "multi.txt" "$cluster_output" "clustered options include matching filename"
assert_contains "Alpha" "$cluster_output" "clustered options include first tag"
assert_contains "Beta" "$cluster_output" "clustered options include second tag"

"$TAG_BIN" --set DirectoryTag "$FIXTURE_DIR"
"$TAG_BIN" --set ChildTag "$CHILD_FILE"
"$TAG_BIN" --set HiddenTag "$HIDDEN_FILE"

recursive_output=$("$TAG_BIN" --list --recursive --no-name "$FIXTURE_DIR")
assert_contains "DirectoryTag" "$recursive_output" "recursive output includes provided directory"
assert_contains "ChildTag" "$recursive_output" "recursive output includes child file"
assert_not_contains "HiddenTag" "$recursive_output" "recursive output skips hidden files by default"

all_output=$("$TAG_BIN" --list --recursive --all --no-name "$FIXTURE_DIR")
assert_contains "HiddenTag" "$all_output" "all recursive output includes hidden files"

slash_output=$("$TAG_BIN" --list --slash "$FIXTURE_DIR")
assert_contains "fixture-dir/" "$slash_output" "slash output marks directories"

enter_output=$("$TAG_BIN" --list --enter --no-name "$FIXTURE_DIR")
assert_contains "DirectoryTag" "$enter_output" "enter output includes provided directory"
assert_contains "ChildTag" "$enter_output" "enter output includes direct child"

nul_output_file="$TMP_DIR/nul-output.bin"
"$TAG_BIN" --list --nul "$MULTI_TAG_FILE" > "$nul_output_file"
python3 - "$nul_output_file" <<'PY'
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
if not data.endswith(b"\0"):
    raise SystemExit("NUL output did not end with NUL")
if b"\n" in data:
    raise SystemExit("NUL output unexpectedly contained newline")
PY

(
    cd "$TMP_DIR"
    default_output=$("$TAG_BIN")
    case "$default_output" in
        *"one.txt"*|*"multi.txt"*|*"untagged.txt"*) ;;
        *) fail "default list without paths enumerates current directory; actual output was <$default_output>" ;;
    esac
)

assert_status 1 "duplicate operations are rejected" "$TAG_BIN" --list --set Alpha "$ONE_TAG_FILE"
assert_contains "Operation mode cannot be respecified" "$LAST_OUTPUT" "duplicate operation error is actionable"

MISSING_FILE="$TMP_DIR/missing.txt"
assert_status 2 "missing paths return operation failure" "$TAG_BIN" --list "$MISSING_FILE"
assert_contains "missing.txt" "$LAST_OUTPUT" "missing path error includes the path"

"$TAG_BIN" --set Red "$ONE_TAG_FILE"
ESC=$(printf '\033')
missing_color_output=$(TAG_FINDER_PREFERENCES_PATH="$TMP_DIR/missing-finder.plist" "$TAG_BIN" --list --color --no-name "$ONE_TAG_FILE")
assert_eq "Red" "$missing_color_output" "missing Finder color preferences do not affect tag output"
assert_not_contains "$ESC[" "$missing_color_output" "color escapes are not emitted for non-terminal output"

BAD_FINDER_PLIST="$TMP_DIR/bad-finder.plist"
printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>values</key><dict/></dict></plist>' > "$BAD_FINDER_PLIST"
bad_color_output=$(TAG_FINDER_PREFERENCES_PATH="$BAD_FINDER_PLIST" "$TAG_BIN" --list --color --no-name "$ONE_TAG_FILE")
assert_eq "Red" "$bad_color_output" "changed Finder color preference shape falls back safely"

UNREADABLE_FINDER_PLIST="$TMP_DIR/unreadable-finder.plist"
printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' > "$UNREADABLE_FINDER_PLIST"
chmod 000 "$UNREADABLE_FINDER_PLIST"
unreadable_color_output=$(TAG_FINDER_PREFERENCES_PATH="$UNREADABLE_FINDER_PLIST" "$TAG_BIN" --list --color --no-name "$ONE_TAG_FILE")
assert_eq "Red" "$unreadable_color_output" "unreadable Finder color preferences fall back safely"

assert_status 0 "find wildcard completes without hanging" "$TAG_BIN" --find '*' "$TMP_DIR"
assert_status 0 "usage wildcard completes without hanging" "$TAG_BIN" --usage '*' "$TMP_DIR"

printf 'integration tests passed\n'
