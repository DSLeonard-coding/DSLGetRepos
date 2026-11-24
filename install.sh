#!/bin/sh
set -eu

REPO_URL="https://github.com/DSLeonard-coding/DSLGetRepos"
REF="${DSL_GET_REPO_REF:-master}"
DEST="${1:-.}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

wget -qO "$TMP_DIR/repo.tar.gz" "$REPO_URL/archive/$REF.tar.gz"
mkdir -p "$TMP_DIR/src" "$DEST"
tar -xz --strip-components=1 -f "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR/src"

cp -r "$TMP_DIR/src/dist/." "$DEST/"
