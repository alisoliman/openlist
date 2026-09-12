#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECKOUTS=${1:?Usage: update-mcp-notices.sh CHECKOUTS_DIRECTORY [--check]}
MODE=${2:---write}
[[ "$MODE" == --write || "$MODE" == --check ]] || { echo "Expected --check or --write" >&2; exit 1; }
mkdir -p .build/tmp
OUT=$(mktemp .build/tmp/mcp-notices.XXXXXX)
trap 'rm -f "$OUT"' EXIT
TARGET=openlist/ThirdPartyNotices.txt

{
    printf 'Openlist - native MCP runtime dependency notices\n'
    printf 'Dependency versions and revisions are pinned in Package.resolved.\n'
    for package in swift-sdk swift-nio swift-system swift-log swift-atomics swift-collections eventsource swift-nio/Sources/CNIOLLHTTP; do
        license=
        for name in LICENSE LICENSE.txt LICENSE.md; do
            if [[ -f "$CHECKOUTS/$package/$name" ]]; then
                license="$CHECKOUTS/$package/$name"
                break
            fi
        done
        [[ -n "$license" ]] || { echo "Missing license for $package; resolve packages first" >&2; exit 1; }
        printf '\n============================================================\n%s\n============================================================\n\n' "$package"
        cat "$license"
        if [[ -f "$CHECKOUTS/$package/NOTICE.txt" ]]; then
            printf '\nNOTICE\n\n'
            cat "$CHECKOUTS/$package/NOTICE.txt"
        fi
    done
} > "$OUT"

if [[ "$MODE" == --check ]]; then
    cmp -s "$OUT" "$TARGET" || {
        echo "MCP license notices are out of date. Run ./Tools/update-mcp-notices.sh $CHECKOUTS" >&2
        exit 1
    }
else
    mv "$OUT" "$TARGET"
fi
