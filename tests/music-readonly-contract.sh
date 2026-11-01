#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
check_absent() {
    local pattern=$1
    shift
    if rg -n --hidden --glob '!tests/music-readonly-contract.sh' "$pattern" "$@"; then
        printf 'Forbidden Music mutation capability found: %s\n' "$pattern" >&2
        fail=1
    fi
}

check_absent 'com\.apple\.iTunes\.library\.read-write|com\.apple\.iTunes\.user-interface' Resources Embrace.xcodeproj
check_absent 'exportSetlist:|exportToPlaylist|Export to (Music|iTunes)' Source Resources
check_absent 'MusicLibrary\.(createPlaylist|edit|add)|SBApplication.*(Music|iTunes)' Source

plutil -lint Resources/Embrace.entitlements >/dev/null
xmllint --noout Resources/Base.lproj/MainMenu.xib
if (( fail )); then exit 1; fi
printf 'Music read-only contract passed.\n'
