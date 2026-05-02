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

if [ ! -x "$TAG_BIN" ]; then
    fail "tag binary not found at $TAG_BIN; run 'make' first or set TAG_BIN"
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tag-tests.XXXXXX")
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ONE_TAG_FILE="$TMP_DIR/one.txt"
MULTI_TAG_FILE="$TMP_DIR/multi.txt"
UNTAGGED_FILE="$TMP_DIR/untagged.txt"
FIXTURE_DIR="$TMP_DIR/fixture-dir"
CHILD_FILE="$FIXTURE_DIR/child.txt"
HIDDEN_FILE="$FIXTURE_DIR/.hidden.txt"

mkdir -p "$FIXTURE_DIR"
printf 'one\n' > "$ONE_TAG_FILE"
printf 'multi\n' > "$MULTI_TAG_FILE"
printf 'none\n' > "$UNTAGGED_FILE"
printf 'child\n' > "$CHILD_FILE"
printf 'hidden\n' > "$HIDDEN_FILE"

"$TAG_BIN" --set Alpha "$ONE_TAG_FILE"
assert_eq "Alpha" "$("$TAG_BIN" --list --no-name "$ONE_TAG_FILE")" "set/list single tag"

"$TAG_BIN" --set Alpha,Beta "$MULTI_TAG_FILE"
assert_eq "Alpha,Beta" "$("$TAG_BIN" --list --no-name "$MULTI_TAG_FILE")" "set/list multiple tags"

assert_eq "" "$("$TAG_BIN" --list --no-name "$UNTAGGED_FILE")" "list untagged file with no-name"

"$TAG_BIN" --add Gamma "$ONE_TAG_FILE"
assert_eq "Alpha,Gamma" "$("$TAG_BIN" --list --no-name "$ONE_TAG_FILE")" "add preserves existing tags"

"$TAG_BIN" --remove Alpha "$ONE_TAG_FILE"
assert_eq "Gamma" "$("$TAG_BIN" --list --no-name "$ONE_TAG_FILE")" "remove one tag"

"$TAG_BIN" --remove '*' "$ONE_TAG_FILE"
assert_eq "" "$("$TAG_BIN" --list --no-name "$ONE_TAG_FILE")" "remove wildcard clears tags"

match_output=$("$TAG_BIN" --match beta --no-name --tags "$ONE_TAG_FILE" "$MULTI_TAG_FILE")
assert_eq "Alpha,Beta" "$match_output" "match is case-insensitive and requires matching files only"

"$TAG_BIN" --set DirectoryTag "$FIXTURE_DIR"
"$TAG_BIN" --set ChildTag "$CHILD_FILE"
"$TAG_BIN" --set HiddenTag "$HIDDEN_FILE"

recursive_output=$("$TAG_BIN" --list --recursive --no-name "$FIXTURE_DIR")
assert_contains "DirectoryTag" "$recursive_output" "recursive output includes provided directory"
assert_contains "ChildTag" "$recursive_output" "recursive output includes child file"
assert_not_contains "HiddenTag" "$recursive_output" "recursive output skips hidden files by default"

all_output=$("$TAG_BIN" --list --recursive --all --no-name "$FIXTURE_DIR")
assert_contains "HiddenTag" "$all_output" "all recursive output includes hidden files"

printf 'integration tests passed\n'
