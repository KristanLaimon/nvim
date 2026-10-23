#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git ls-files -z | {
    total=0
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            bytes=$(wc -c < "$file")
            total=$((total + bytes))
        fi
    done
    printf '%s\n' "$total" | awk '{ printf "Tracked files: %.2f MiB (%s bytes)\n", $1 / 1048576, $1 }'
}
