#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
for editor in vim nvim; do
    mkdir -p "$work/$editor"
    printf 'Testing %s\n' "$editor"
    if [ "$editor" = vim ]; then
        set -- vim -Nu NONE -i NONE -n -es
    else
        set -- nvim --headless -u NONE -i NONE -n
    fi
    if ! HOME="$work/$editor" XDG_CONFIG_HOME="$work/$editor/.config" VIMPROJECT_ROOT="$root" "$@" -S tests/test_vimproject.vim; then
        if [ -f "$work/$editor/test-errors" ]; then
            while IFS= read -r line; do printf '%s\n' "$line"; done < "$work/$editor/test-errors"
        fi
        exit 1
    fi
done
